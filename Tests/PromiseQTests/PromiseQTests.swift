import XCTest

//@testable import PromiseQ
import PromiseQ

#if os(macOS)
	typealias UIImage = NSImage
#endif

extension DispatchQueue {
	
	static var queues: [String : DispatchQueue] = {
		let array: [DispatchQueue] = [.main,
									  .global(qos: .background),
									  .global(qos: .utility),
									  .global(qos: .default),
									  .global(qos: .userInitiated),
									  .global(qos: .userInteractive)]
		return Dictionary(uniqueKeysWithValues: array.map { ($0.label, $0) })
	}()
	
	static var current: DispatchQueue? {
		let label = String(cString: __dispatch_queue_get_label(nil));
		return Self.queues[label]
	}
}

extension XCTestCase {
	
	func wait(count: Int, timeout: TimeInterval = 1, name: String = #function, closure: ([XCTestExpectation]) -> Void) {
		let expectations = (0..<count).map { _ in expectation(description: name) }
		
		closure(expectations)
		
		wait(for: expectations, timeout: timeout)
	}
	
	func wait(timeout: TimeInterval = 1, name: String = #function, closure: (XCTestExpectation) -> Void) {
		wait(count: 1, timeout: timeout, name: name) { expectations in
			closure(expectations[0])
		}
	}
}

// MARK: -

/// Github user
struct User : Codable {
	let login: String
	let avatar_url: String
}

class TimeOutTask : Asyncable {
	let timeOut: TimeInterval
	var work: DispatchWorkItem?
	let fire: () -> Void
	
	init(timeOut: TimeInterval, _ fire: @escaping () -> Void) {
		self.timeOut = timeOut
		self.fire = fire
	}
	
	// MARK: Asyncable
	
	func suspend() {
		cancel()
	}
	
	func resume() {
		work = DispatchWorkItem(block: self.fire)
		DispatchQueue.global().asyncAfter(deadline: .now() + timeOut, execute: work!)
	}
	
	func cancel() {
		work?.cancel()
		work = nil
	}
}

// MARK: -

let debugDateFormatter: DateFormatter = {
	let dateFormatter = DateFormatter()
	dateFormatter.dateFormat = "HH:mm:ss:SSS"
	return dateFormatter
}()

func dlog(_ items: String..., icon: Character = "▶️", file: String = #file, function: String = #function, line: UInt = #line) {
	let text = items.count > 0 ? items.joined(separator: " ") : function
	let fileName = NSString(string: file).lastPathComponent
	let time = debugDateFormatter.string(from: Date())
	
	print("[\(time)] [DLOG] \(icon) <\(fileName):\(line)>", text)
}

func dlog(error: Error, file: String = #file, function: String = #function, line: UInt = #line) {
	dlog("Error: \(error.localizedDescription)", icon: "⚠️", file: file, function: function, line: line)
}

func asyncAfter(_ sec: Double = 0.25, closure: @escaping (() -> Void) ) {
	DispatchQueue.global().asyncAfter(deadline: .now() + sec, execute: closure)
}

// MARK: -

var GitHubHeaders: [String : String]? = {
	if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
		return ["Authorization" : "token \(token)"]
	}
	return nil
}()

// Url with large data to fetch
let url = "https://developer.apple.com/swift/blog/"

final class CommonTests: XCTestCase {
	
	func test_AutoRun() {
		wait(count: 2) { expectations in

			Promise {
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[0].fulfill()
			}
			
			Promise<Void> { resolve, reject in
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[1].fulfill()
			}
		}
	}
	
	func test_Resolve() {
		wait { expectation in
			let promise = Promise.resolve(200)
			promise.then {
				XCTAssert($0 == 200)
				expectation.fulfill()
			}
		}
	}
	
	func test_Reject() {
		wait { expectation in
			let promise = Promise<Void>.reject("Some error")
			promise.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Some error")
				expectation.fulfill()
			}
		}
	}
	
    func test_CreateOnMainQueue() {
		wait { expectation in
			Promise {
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectation.fulfill()
			}
		}
    }
	
	func test_CreateOnGlobalQueue() {
		wait { expectation in
			DispatchQueue.global().async {
				Promise {
					XCTAssert(DispatchQueue.current == DispatchQueue.global())
					expectation.fulfill()
				}
			}
		}
    }
	
	func thread(expectation: XCTestExpectation) {
		Promise {
			XCTAssert(DispatchQueue.current == DispatchQueue.global())
		}
		.then {
			XCTAssert(DispatchQueue.current == DispatchQueue.global())
			expectation.fulfill()
		}
	}
	
	func test_CreateOnThread() {
		wait { expectation in
			Thread.detachNewThreadSelector(#selector(thread), toTarget: self, with: expectation);
		}
    }
	
	func test_RunOnQueues() {
		wait(count: 5) { expectations in
			Promise (.main) {
				XCTAssert(DispatchQueue.current == DispatchQueue.main)
				expectations[0].fulfill()
			}
			.then(.global()) { _ in
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[1].fulfill()
			}
			.then(.global(qos: .utility)) { _ in
				XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .utility))
				expectations[2].fulfill()
			}
			.then { _ in
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[3].fulfill()
			}
			.then(.global(qos: .background)) { _ in
				XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .background))
				expectations[4].fulfill()
			}
		}
	}
	
	func test_ThrowNoCatch() {
		wait { expectation in
			expectation.isInverted = true
			
			Promise { () -> Void in
				throw "Some Error"
			}
			.then {
				expectation.fulfill()
			}
		}
	}
	
	func test_CatchThen() {
		wait { expectation in
			Promise {
				return 100
			}
			.catch { error in
				XCTFail()
			}
			.then {
				expectation.fulfill()
			}
		}
	}
		
	func test_ThrowCatch() {
		wait { expectation in
			Promise { () -> Void in
				throw "Error"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func test_ThrowCatchThen() {
		wait { expectation in
			Promise {  () -> Void in
				throw "Some Error"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Some Error")
			}
			.then {
				expectation.fulfill()
			}
		}
	}
	
	func test_Rethrow() {
		wait { expectation in
			Promise {  () -> Void in
				throw "Error1"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error1")
				throw "Error2"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error2")
				throw error
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error2")
				expectation.fulfill()
			}
		}
	}
	
	func test_AsyncCatch() {
		wait { expectation in
			Promise<Int> { resolve, reject in
				asyncAfter {
					reject("Error")
					
					resolve(200) // Must be skipped
				}
			}
			.then { value in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func test_AsyncThrow() {
		wait(count: 2) { expectations in
			Promise<Int> { resolve, reject in
				asyncAfter {
					resolve(200)
				}
				throw "Error1"
			}
			.then { value in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error1")
				expectations[0].fulfill()
			}
			.then { (_, resolve: @escaping (Int) -> Void, reject) in
				asyncAfter {
					resolve(200) // Skip
				}
				throw "Error2"
				
			}
			.then { value in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error2")
				expectations[1].fulfill()
			}
		}
	}
	
	func test_Then() {
		wait { expectation in
			Promise {
				return "Hello"
			}
			.then {
				XCTAssert($0 == "Hello")
				expectation.fulfill()
			}
		}
	}
	
	func test_ThenThrow() {
		wait(count: 3) { expectations in
			expectations[1].isInverted = true
			
			Promise {
				return "Hello"
			}
			.then { (value) -> Void in
				XCTAssert(value == "Hello")
				expectations[0].fulfill()
				throw "Error"
			}
			.then {
				expectations[1].fulfill()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[2].fulfill()
			}
		}
	}
	
	func test_AsyncThen() {
		wait { expectation in
			Promise<String> { resolve, reject in
				asyncAfter {
					resolve("Hello")
					
					reject("Error") // Must be skipped
				}
			}
			.then {
				XCTAssert($0 == "Hello")
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_AsyncThenAsyncThen() {
		wait { expectation in
			Promise<String> { resolve, reject in
				asyncAfter {
					resolve("Hello")
				}
			}
			.then { (str, resolve: (Int)->Void, reject) in
				resolve(str.count)
				
				reject("Error") // Must be skipped
			}
			.then {
				XCTAssert($0 == 5)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_ThenReject() {
		wait { expectation in
			expectation.isInverted = true
			
			Promise.resolve(404)
			.then { (value: Int, resolve: (Int)->Void, reject) in
				if value == 404 {
					reject("Error")
				}
				resolve(value)
			}
			.then { (value: Int , resolve: (Int)->Void, reject) in
				expectation.fulfill()
				resolve(value)
			}
		}
	}
	
	func test_FinallyThen() {
		wait(count: 3) { expectations in
			Promise {
				return 200
			}
			.finally {
				expectations[0].fulfill()
			}
			.then { value in
				XCTAssert(value == 200)
				expectations[1].fulfill()
			}
			.finally {
				expectations[2].fulfill()
			}
		}
	}
	
	func test_FinallyCatch() {
		wait(count: 3) { expectations in
			Promise<Int> { resolve, reject in
				asyncAfter {
					reject("Error")
					
					resolve(200) // Must be skipped
				}
			}
			.finally {
				expectations[0].fulfill()
			}
			.then { value in
				XCTFail() // Must be skipped
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[1].fulfill()
			}
			.finally {
				expectations[2].fulfill()
			}
		}
	}
	

	func test_Promise() {
		wait { expectation in
			
			Promise<Int> { () -> Promise<Int> in
				let status = 200
				return Promise {
					Promise.resolve(status)
				}
			}
			.then { value in
				XCTAssert(value == 200)
				
				return Promise {
					value / 10
				}
				.then {
					$0 / 2
				}
			}
			.then { (value: Int) -> Promise<Int> in
				XCTAssert(value == 10)
				
				return
					Promise.resolve(value)
					.then { value in
						Promise {
							value * 2
						}
						.then {
							$0 * 10
						}
					}
			}
			.then {
				XCTAssert($0 == 200)
				expectation.fulfill()
			}
		}
	}
	
	func test_PromiseThrow() {
		wait(count:3) { expectations in
			expectations[0].isInverted = true
			
			Promise {
				Promise { () -> Void in
					throw "Error"
				}
			}
			.then {
				expectations[0].fulfill() // Must be skipped
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
			}
			.then { (value) -> Promise<Int> in
				expectations[1].fulfill() // Must be skipped
				return Promise.reject("Error")
			}
			.then { promise in
				expectations[0].fulfill() // Must be skipped
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[2].fulfill()
			}
		}
	}
	
	func test_ThenPromiseSyncReject() {
		wait(count:2) { expectations in
			expectations[0].isInverted = true
			
			Promise.resolve(200)
			.then { value in
				Promise { () -> Int in
					if value == 200 {
						throw "Error"
					}
					return value / 10
				}
				.catch { error in
					XCTAssert(error.localizedDescription == "Error")
					throw error
				}
			}
			.then { value in
				expectations[0].fulfill() // Must be skipped
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[1].fulfill()
			}
		}
	}
	
	func test_ThenPromiseAsync() {
		wait { expectation in
			Promise.resolve(200)
			.then { value in
				Promise { resolve, reject in
					asyncAfter {
						resolve(value / 10)
					}
				}
				.then {
					$0 / 2
				}
			}
			.then {
				XCTAssert($0 == 10)
				expectation.fulfill()
			}
		}
	}
	
	func test_ThenPromiseAsyncReject() {
		wait(count: 2) { expectations in
			expectations[0].isInverted = true
			
			Promise.resolve(200)
			.then { value in
				Promise { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				}
			}
			.then {
				expectations[0].fulfill() // Skip
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[1].fulfill()
			}
		}
	}
	
	func test_TimeOutSync() {
		wait(count: 4) { expectations in
			Promise(timeout: 0.1) {
				Thread.sleep(forTimeInterval: 0.3)
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.timedOut = error {
					expectations[0].fulfill()
				}
			}
			.then(timeout: 0.1) {
				Thread.sleep(forTimeInterval: 0.3)
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.timedOut = error {
					expectations[1].fulfill()
				}
			}
			.then(timeout: 0.1) { _, resolve, reject in
				asyncAfter {
					resolve(())
				}
			}
			.then { value in
				XCTFail()
			}
			.catch(timeout: 0.1) { error in
				if case PromiseError.timedOut = error {
					expectations[2].fulfill()
				}
				Thread.sleep(forTimeInterval: 0.3)
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.timedOut = error {
					expectations[3].fulfill()
				}
			}
		}
	}
	
	func test_TimeOutAsync() {
		wait(count: 2) { expectations in
			Promise(timeout: 0.1) { resolve, reject in
				asyncAfter {
					resolve(200)
				}
			}
			.then { value in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.timedOut = error {
					expectations[0].fulfill()
				}
			}
			.then(timeout: 0.1) { _, resolve, reject in
				asyncAfter {
					resolve(200)
				}
			}
			.then { value in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.timedOut = error {
					expectations[1].fulfill()
				}
			}
		}
	}
	
	func test_RetrySync() {
		wait { expectation in
			var count = 2
			Promise(retry: 2) { () -> String in
				if count > 0 {
					count -= 1
					throw "fail"
				}
				return "done1"
			}
			.then(retry: 2) { value -> String in
				XCTAssert(value == "done1")
				
				if count < 2 {
					count += 1
					throw "fail"
				}
				
				return "done2"
			}
			.then(retry: 2) { value -> Promise<String> in
				XCTAssert(value == "done2")
				
				if count > 0 {
					count -= 1
					throw "fail"
				}
				return Promise.resolve("done3")
			}
			.then { value -> Promise<String> in
				XCTAssert(value == "done3")
				
				return Promise(retry: 2) { () -> String in
					if count < 2 {
						count += 1
						throw "fail"
					}
					return "done4"
				}
			}
			.then { value in
				XCTAssert(value == "done4")
				throw "catch"
			}
			.catch(retry: 2) { error in
				XCTAssert(error.localizedDescription == "catch")
				
				if count > 0 {
					count -= 1
					throw "fail"
				}
			}
			.then {
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_RetryAsync() {
		wait { expectation in
			var count = 2
			Promise<String>(retry: 2) { resolve, reject in
				if count > 0 {
					count -= 1
					reject("fail")
				}
				resolve("done1")
			}
			.then(retry: 2) { (value, resolve: (String) -> Void, reject) in
				XCTAssert(value == "done1")
				
				if count < 2 {
					count += 1
					reject("fail")
				}
				
				resolve("done2")
			}
			.then { value in
				XCTAssert(value == "done2")
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_All() {
		wait { expectation in
			Promise.all(
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise { resolve, reject in
					asyncAfter(0.5) {
						resolve("World")
					}
				}
			)
			.then { results in
				XCTAssert(results.count == 2)
				XCTAssert(results[0] == "Hello")
				XCTAssert(results[1] == "World")
				expectation.fulfill()
			}
		}
	}
	
	func test_AllCancel() {
		wait(count:2) { expectations in
			expectations[0].isInverted = true
			
			let promise = Promise.all(
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise { resolve, reject in
					asyncAfter {
						resolve("World")
					}
				}
			)
			.then { results in
				expectations[0].fulfill()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
			
			asyncAfter(0.1) {
				promise.cancel()
			}
		}
	}
	
	func test_AllEmpty() {
		wait { expectation in
			let promises = [Promise<Int>]()
			
			Promise.all(promises)
			.then { results in
				XCTAssert(results.count == 0)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_AllAny() {
		wait { expectation in
			Promise<Any>.all(
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise.resolve(200)
			)
			.then { results in
				XCTAssert(results.count == 2)
				XCTAssert(results[0] as! String == "Hello")
				XCTAssert(results[1] as! Int == 200)
				expectation.fulfill()
			}
		}
	}
	
	func test_AllCatch() {
		wait { expectation in
			Promise.all(
				Promise { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				},
				Promise.resolve(3)
			)
			.then { results in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func test_AllSettled() {
		wait { expectation in
			Promise<Any>.all(settled: true,
				Promise { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				},
				Promise.resolve(200),
				Promise { resolve, reject in
					asyncAfter {
						resolve(3.14)
					}
				}
			)
			.then { results in
				XCTAssert(results.count == 3)
				XCTAssert(results[0] as! String == "Error")
				XCTAssert(results[1] as! Int == 200)
				XCTAssert(results[2] as! Double == 3.14)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_AllSuppendResume() {
		wait { expectation in
			let promise = Promise.all(
				Promise { resolve, reject in
					asyncAfter { resolve(200) }
				},
				Promise.resolve(300)
			)
			.then { results in
				XCTAssert(results.count == 2)
				XCTAssert(results[0] == 200)
				XCTAssert(results[1] == 300)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
			
			asyncAfter(0.1) { promise.suspend() }
			asyncAfter(0.5) { promise.resume() }
		}
	}
	
	func test_RaceEmpty() {
		wait { expectation in
			let promises = [Promise<Any>]()
			
			Promise.race(promises)
			.then { result in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.empty = error {
					expectation.fulfill()
					XCTAssert(error.localizedDescription == "The Promises empty.")
				}
			}
		}
	}
	
	func test_RaceCancel() {
		wait(count: 2) { expectations in
			expectations[0].isInverted = true
			
			let promise = Promise.race(
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise { resolve, reject in
					asyncAfter {
						resolve("World")
					}
				}
			)
			.then { results in
				expectations[0].fulfill()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
			
			asyncAfter(0.1) {
				promise.cancel()
			}
		}
	}
	
	func test_RaceThen() {
		wait { expectation in
			Promise<Any>.race(
				Promise { resolve, reject in
					asyncAfter {
						resolve(200)
					}
				},
				Promise { resolve, reject in
					asyncAfter(0.5) {
						resolve("Result")
					}
				},
				Promise { resolve, reject in
					asyncAfter(1) {
						reject("Error")
					}
				}
			)
			.then { result in
				XCTAssert(result as! Int == 200)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_RaceCatch() {
		wait { expectation in
			Promise.race(
				Promise { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				},
				Promise { resolve, reject in
					asyncAfter(1) {
						resolve(3)
					}
				}
			)
			.then { result in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func test_AnyEmpty() {
		wait { expectation in
			let promises = [Promise<Any>]()
			
			Promise.any(promises)
			.then { result in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.empty = error {
					expectation.fulfill()
					XCTAssert(error.localizedDescription == "The Promises empty.")
				}
			}
		}
	}
	
	func test_Any() {
		wait { expectation in
			Promise<Any>.any(
				Promise {
					throw "Fatal"
				},
				Promise { resolve, reject in
					reject("Fail")
				},
				Promise { resolve, reject in
					asyncAfter {
						resolve(200)
					}
				},
				Promise { resolve, reject in
					asyncAfter(0.5) {
						resolve("OK")
					}
				}
			)
			.then { result in
				XCTAssert(result is Int)
				XCTAssert(result as! Int == 200)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_AnyCancel() {
		wait(count: 2) { expectations in
			expectations[0].isInverted = true
			
			let promise = Promise<Any>.any(
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise { resolve, reject in
					asyncAfter {
						resolve(200)
					}
				}
			)
			.then { results in
				expectations[0].fulfill()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
			
			asyncAfter(0.1) {
				promise.cancel()
			}
		}
	}
	
	func test_AnyReject() {
		wait { expectation in
			let promise = Promise<Any> { resolve, reject in
				asyncAfter { resolve(200) }
			}
			
			Promise.any(
				Promise(timeout: 0.1) { resolve, reject in
				},
				promise
			)
			.then { result in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == PromiseError.aggregate([Error]()).localizedDescription)
				
				if case let PromiseError.aggregate(errors) = error {
					XCTAssert(errors.count == 2)
					XCTAssert(errors[0].localizedDescription == PromiseError.timedOut.localizedDescription)
					XCTAssert(errors[1].localizedDescription == PromiseError.cancelled.localizedDescription)
					expectation.fulfill()
				}
			}
			
			promise.cancel()
		}
	}
	
	func test_Cancel() {
		wait(count: 4) { expectations in
			let p = Promise {
				XCTFail()
			}
			.then {
				XCTFail()
			}
			.then {
				Promise { XCTFail() }
			}
			.finally {
				expectations[0].fulfill()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
			.finally {
				expectations[2].fulfill()
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[3].fulfill()
				}
			}
			
			DispatchQueue.global().async { p.cancel() }
		}
	}
	
	func test_CancelDouble() {
		wait { expectation in
			let p = Promise {
				XCTFail()
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectation.fulfill()
				}
			}
			
			p.cancel()
			p.cancel()
		}
	}
	
	func test_CancelInside() {
		wait(count: 2) { expectations in
			let p = Promise {
				expectations[0].fulfill()
			}
			p.then {
				p.cancel()
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
		}
	}
	
	func test_CancelAsync() {
		wait(count: 3) { expectations in
		
			let p = Promise { resolve, reject in
				asyncAfter {
					resolve(200)
				}
			}
			.then { value, resolve, reject in
				XCTAssert(value == 200)
				expectations[0].fulfill()
				
				asyncAfter {
					resolve(())
				}
			}
			.then {
				XCTFail()
			}
			.finally {
				expectations[1].fulfill()
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[2].fulfill()
				}
			}
			
			asyncAfter(0.4) {
				p.cancel()
			}
		}
	}
	
	func test_CancelTimeout() {
		wait { expectation in
			
			let p = Promise(timeout: 10) { resolve, reject in
			}
			.then {
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectation.fulfill()
				}
			}
			
			asyncAfter {
				p.cancel()
			}
		}
	}
	
	func test_Suspend() {
		wait { expectation in
			expectation.isInverted = true
		
			let p = Promise {
				expectation.fulfill()
			}
			.finally {
				expectation.fulfill()
			}
			
			p.suspend()
		}
	}
	
	func test_SuspendInside() {
		wait { expectation in
			expectation.isInverted = true
			
			let p = Promise {
			}
			p.then {
				p.suspend()
			}
			.finally {
				expectation.fulfill()
			}
			.then {
				expectation.fulfill()
			}
		}
	}
	
	func test_SuspendResume() {
		wait { expectation in
			var str = ""
			
			let p = Promise<String> { resolve, reject in
				asyncAfter {
					resolve("Hello")
				}
			}
			.then { value, resolve, reject in
				str += value
				
				asyncAfter {
					resolve(" World!")
				}
			}
			.then { (value: String) -> Void in
				str += value
				XCTAssert(str == "Hello World!")
				expectation.fulfill()
			}
			
			asyncAfter {
				p.suspend()
				p.suspend() // Must be skipped
			}
			
			asyncAfter(0.5) {
				p.resume()
				p.resume()
			}
		}
	}
	
	func test_SuspendCancelResume() {
		wait { expectation in
			expectation.isInverted = true
			
			let p = Promise {
				return 200
			}
			.then {
				XCTAssert($0 == 200)
				expectation.fulfill()
			}
			
			p.suspend()
			
			asyncAfter {
				p.cancel()
			}
			
			asyncAfter(0.5) {
				p.resume()
			}
		}
	}
	
	func test_AsyncableSuspendResume() {
		wait(timeout: 10) { expectation in
			let p = fetch(url)
			p.then { (data, resolve: @escaping (String)->Void, reject, task) in
				task = TimeOutTask(timeOut: 1) { resolve("fired") }
				task?.resume()
				
				asyncAfter {
					p.suspend()
				}
				
				asyncAfter(1) {
					p.resume()
				}
			}
			.then { text in
				XCTAssert(text == "fired")
				expectation.fulfill()
			}
			.catch { error in
				dlog(error: error)
			}
			
			// Fetch
			asyncAfter(1) {
				p.suspend()
			}
			asyncAfter(2) {
				p.resume()
			}
		}
	}
	
	func test_AsyncableCancel() {
		wait(timeout: 2) { expectation in
			expectation.isInverted = true
			
			let p = Promise<String> { resolve, reject, task in
				task = TimeOutTask(timeOut: 1) { resolve("fired") }
				task?.resume()
			}
			.then { text in
				XCTAssert(text == "fired")
				expectation.fulfill()
			}
			
			asyncAfter {
				p.cancel()
			}
		}
	}
	
	func test_AsyncableAll() {
		wait(timeout: 10) { expectation in
			let p = Promise.all (
				fetch(url),
				fetch(url)
			)
			.then { results in
				XCTAssert(results.count > 0)
				expectation.fulfill()
			}
			.catch { error in
				dlog(error: error)
			}
			
			// Fetch
			asyncAfter(1) {
				p.suspend()
			}
			asyncAfter(2) {
				p.resume()
			}
		}
	}
	
	func test_Async() {
		wait { expectation in
			async {
				expectation.fulfill()
			}
		}
	}
	
	func test_DoAwait() {
		wait { expectation in
			do {
				let text = try Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				}.await()
				
				XCTAssert(text == "Hello")
				expectation.fulfill()
			}
			catch {
			}
		}
	}
	
	func test_AsyncAwait() {
		wait { expectation in
			async {
				let text = try async { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				}.await()
				
				XCTAssert(text == "Hello")
				expectation.fulfill()
			}
		}
	}
	
	func test_AsyncAwaitThrow() {
		wait(count: 2) { expectations in
			expectations[0].isInverted = true
			
			async {
				try async<Void> { resolve, reject in
					reject("Error")
				}.await()
				
				expectations[0].fulfill() // Must be skipped
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectations[1].fulfill()
			}
		}
	}
	
	func test_AsyncAwaitCancel() {
		wait(count: 2) { expectations in
			expectations[0].isInverted = true
			
			async {
				let promise = Promise { resolve, reject in
					asyncAfter {
						resolve(200)
					}
				}
				
				asyncAfter(0.1) {
					promise.cancel()
				}
				
				_ = try promise.await()
				
				expectations[0].fulfill() // Must be skipped
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
		}
	}
	
}

final class FetchTests: XCTestCase {
	
	struct JSONResponse : Codable {
		let data: String?
		let url: String
	}
	
	func test_badURL() {
		wait(count: 2) { expectations in
			Promise.any(
				fetch(""),
				upload("", data: Data()),
				download("")
			)
			.then { result in
				XCTFail()
			}
			.catch { error in
				if case let PromiseError.aggregate(errors) = error {
					errors.forEach {
						XCTAssert($0.localizedDescription == "Bad URL")
					}
					expectations[0].fulfill()
				}
			}
			
			let url = URL(string: "123")!
			let request = URLRequest(url: url)
			Promise.any(
				fetch("123"),
				URLSession.shared.fetch(url),
				URLSession.shared.fetch(request),
				upload("123", data: Data()),
				download("123")
			)
			.then { result in
				XCTFail()
			}
			.catch { error in
				if case let PromiseError.aggregate(errors) = error {
					errors.forEach {
						XCTAssert($0.localizedDescription == "Not HTTP")
					}
					expectations[1].fulfill()
				}
			}
		}
	}
	
	func test_get_404() {
		wait { expectation in
			let path = "https://postman-echo.com/notfound"
			fetch(path)
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "HTTP 404 - not found")
				expectation.fulfill()
			}
		}
	}
	
	func test_get() {
		wait { expectation in
			let path = "https://postman-echo.com/get"
			fetch(path)
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let json = try JSONDecoder().decode(JSONResponse.self, from: data)
				XCTAssert(json.url == path)
				
				guard let text = response.text else {
					throw "No text"
				}
				XCTAssert(!text.isEmpty)
				
				guard let dict = response.json as? [String : Any] else {
					throw "No json dict"
				}
				XCTAssert(dict.count > 0)
				
				XCTAssert(response.location == nil)

				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_head() {
		wait(timeout: 2) { expectation in
			let path = "https://google.com"
			fetch(path, method: .HEAD)
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				XCTAssert(data.count == 0)
				
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_post() {
		wait { expectation in
			let path = "https://postman-echo.com/post"
			let text = "hello"
			fetch(path, method: .POST, headers: ["Content-Type": "text/plain"], body: text.data(using: .utf8))
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let json = try JSONDecoder().decode(JSONResponse.self, from: data)
				XCTAssert(json.data == text)
				XCTAssert(json.url == path)
				
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_put() {
		wait { expectation in
			let path = "https://postman-echo.com/put"
			let text = "hello"
			fetch(path, method: .PUT, headers: ["Content-Type": "text/plain"], body: text.data(using: .utf8))
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let json = try JSONDecoder().decode(JSONResponse.self, from: data)
				XCTAssert(json.data == text)
				XCTAssert(json.url == path)
				
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_patch() {
		wait { expectation in
			let path = "https://postman-echo.com/patch"
			let text = "hello"
			fetch(path, method: .PATCH, headers: ["Content-Type": "text/plain"], body: text.data(using: .utf8))
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let json = try JSONDecoder().decode(JSONResponse.self, from: data)
				XCTAssert(json.data == text)
				XCTAssert(json.url == path)
				
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_delete() {
		wait { expectation in
			let path = "https://postman-echo.com/delete"
			let text = "hello"
			fetch(path, method: .DELETE, headers: ["Content-Type": "text/plain"], body: text.data(using: .utf8))
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let json = try JSONDecoder().decode(JSONResponse.self, from: data)
				XCTAssert(json.data == text)
				XCTAssert(json.url == path)
				
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func test_fetchSuspend() {
		wait (timeout: 2){ expectation in
			expectation.isInverted = true
			
			let promise = fetch("https://google.com")
			.then { response in
				expectation.fulfill()
			}
			.catch { error in
				expectation.fulfill()
			}
			
			asyncAfter(0.1) {
				promise.suspend()
			}
		}
	}
	
	func test_fetchSuspendResume() {
		wait(timeout: 3) { expectation in
			
			let promise = fetch("https://google.com")
			.then { response in
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
			
			asyncAfter {
				promise.suspend()
			}
			
			asyncAfter(0.5) {
				promise.resume()
			}
		}
	}
	
	func test_fetchCancel() {
		wait (timeout: 2){ expectation in
			
			let promise = fetch("https://google.com")
			.then { response in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectation.fulfill()
				}
			}
			
			asyncAfter(0.1) {
				promise.cancel()
			}
		}
	}
	
	func test_fetchSuspendCancelResume() {
		wait(count:2) { expectations in
			expectations[0].isInverted = true
			
			let promise = fetch("https://google.com")
			.then { response in
				expectations[0].fulfill()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectations[1].fulfill()
				}
			}
			
			asyncAfter(0.01) {
				promise.suspend()
			}
			
			asyncAfter(0.3) {
				promise.cancel()
			}
			
			asyncAfter(0.6) {
				promise.resume()
			}
		}
	}
	
	func test_download() {
		wait(count:3, timeout: 3) { expectations in
			expectations[2].isInverted = true
			
			download("http://speedtest.tele2.net/1MB.zip") { task, written, total in
				let percent = Double(written) / Double(total)
				if percent == 1.0 {
					expectations[0].fulfill()
				}
			}
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let location = response.location else {
					throw "No location"
				}
				
				XCTAssert(FileManager.default.fileExists(atPath: location.path))
				
				guard let data = response.data else {
					throw "No data"
				}
				
				XCTAssert(data.count > 0)
				
				// Remove file
				try FileManager.default.removeItem(atPath: location.path)
				XCTAssert(response.text == nil)
				XCTAssert(response.json == nil)
				
				expectations[1].fulfill()
			}
			.catch { error in
				XCTFail()
				dlog(error: error)
			}
		}
	}
	
	func test_downloadCancel() {
		wait(timeout: 3) { expectation in
			
			let promise = download("http://speedtest.tele2.net/1MB.zip") { task, written, total  in
				let percent = Double(written) / Double(total)
				if percent == 1.0 {
					XCTFail()
				}
			}
			.then { response in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectation.fulfill()
				}
			}
			
			asyncAfter(0.5) {
				promise.cancel()
			}
		}
	}
	
	// https://c.speedtest.net/speedtest-servers-static.php
	let uploadURL = "http://speedtest.lantrace.net:8080/speedtest/upload.php"
	//let uploadURL = "http://speedtest.tele2.net/upload.php"
	
	func test_uploadData() {
		wait(count:2, timeout: 3) { expectations in
			let data = Data(Array(repeating: UInt8(0), count: 1024 * 1024)) // 1MB
			upload(uploadURL, data: data) { task, sent, total in
				let percent = Double(sent) / Double(total)
				if percent == 1.0 {
					expectations[0].fulfill()
				}
			}
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				expectations[1].fulfill()
			}
			.catch { error in
				XCTFail()
				dlog(error: error)
			}
		}
	}
	
	func test_uploadFile() {
		wait(count:3, timeout: 3) { expectations in
			let url = URL(fileURLWithPath: NSTemporaryDirectory() + "upload.tmp")
			
			// File not found
			upload(uploadURL, file: URL(fileURLWithPath: NSTemporaryDirectory() + "notfound.tmp"))
			.then { _ in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "File not found")
				expectations[0].fulfill()
			}
				
			let data = Data(Array(repeating: UInt8(0), count: 1024 * 1024)) // 1MB
			try? data.write(to: url)
			
			// Upload file
			upload(uploadURL, file: url) { task, sent, total in
				let percent = Double(sent) / Double(total)
				if percent == 1.0 {
					expectations[1].fulfill()
				}
			}
			.then { response in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				expectations[2].fulfill()
			}
			.catch { error in
				XCTFail()
				dlog(error: error)
			}
		}
	}
	
	func test_uploadCancel() {
		wait(timeout: 3) { expectation in
			let data = Data(Array(repeating: UInt8(0), count: 1024 * 1024)) // 1MB
			let promise = upload(uploadURL, data: data) { task, written, total  in
				let percent = Double(written) / Double(total)
				if percent == 1.0 {
					XCTFail()
				}
			}
			.then { response in
				XCTFail()
			}
			.catch { error in
				if case PromiseError.cancelled = error {
					expectation.fulfill()
				}
			}
			
			asyncAfter {
				promise.cancel()
			}
		}
	}
}

final class LeakTests: XCTestCase {

	func test_Leak() {
		wait(timeout: 1) { expectation in
			let promise = Promise { return 200 }
			.then { _ in }
			.then { (_, resolve: @escaping (Int) -> Void, reject) in
				asyncAfter {
					resolve(300)
				}
			}
			.then { _ in throw "error" }
			.catch { _ in }
			
			promise.onDeinit {
				expectation.fulfill()
			}
		}
	}
	
	func test_LeakAll() {
		wait(count: 3) { expectations in
			
			let promise1 = Promise { return 200 }
			promise1.onDeinit {
				expectations[0].fulfill()
			}
			
			let promise2 = Promise { return 300 }
			promise2.onDeinit {
				expectations[1].fulfill()
			}
			
			let promiseAll = Promise.all (promise1, promise2)
				.then { _ in
				}
			promiseAll.onDeinit {
				expectations[2].fulfill()
			}
		}
	}
}
	
final class SampleTests: XCTestCase {
	
	/// Load avatars of first 30 GitHub users
	func test_SampleThen() {
		wait(timeout: 4) { expectation in
			fetch("https://api.github.com/users", headers: GitHubHeaders, retry: 3)
			.then { response -> [User] in
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				return try JSONDecoder().decode([User].self, from: data)
			}
			.then { users -> Promise<Array<HTTPResponse>> in
				return Promise.all(
					users
					.map { fetch($0.avatar_url) }
				)
			}
			.then { responses in
				responses
					.compactMap { $0.data }
					.compactMap { UIImage(data: $0)}
			}
			.then(.main) { images in
				XCTAssert(DispatchQueue.current == DispatchQueue.main)
				XCTAssert(images.count == 30)
				expectation.fulfill()
			}
			.catch { error in
				dlog(error: error)
			}
		}
	}
	
	func test_SampleAwait() {
		wait(timeout: 4) { expectation in
			async {
				let response = try fetch("https://api.github.com/users", headers: GitHubHeaders, retry: 3).await()
				guard response.ok else {
					throw response.statusCodeDescription
				}
				
				guard let data = response.data else {
					throw "No data"
				}
				
				let users = try JSONDecoder().decode([User].self, from: data)
				
				let images =
					try async.all(
						users
						.map { fetch($0.avatar_url) }
					).await()
					.compactMap { $0.data }
					.compactMap { UIImage(data: $0) }
				
				async(.main) {
					XCTAssert(DispatchQueue.current == DispatchQueue.main)
					XCTAssert(images.count == 30)
					expectation.fulfill()
				}
			}
			.catch { error in
				dlog(error: error)
				XCTFail()
			}
		}
	}
}
