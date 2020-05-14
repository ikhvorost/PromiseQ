
import XCTest
@testable import PromiseQ

/// String errors
extension String : LocalizedError {
	public var errorDescription: String? { return self }
}

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

func asyncAfter(_ sec: Double = 0.25, closure: @escaping (() -> Void) ) {
	DispatchQueue.global().asyncAfter(deadline: .now() + sec) {
		closure()
    }
}

/// GitHub user fields
struct User : Codable {
	let login: String
	let avatar_url: String
}

/// Make a HTTP request to fetch data by a path
func fetch(_ path: String) -> Promise<Data> {
	Promise<Data> { resolve, reject in
		guard let url = URL(string: path) else {
			reject("Bad path")
			return
		}
		
		var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 10)
			
		// GitHub auth
		if let token = ProcessInfo.processInfo.environment["GITHUB_TOKEN"] {
			request.addValue("token \(token)", forHTTPHeaderField: "Authorization")
		}
		
		URLSession.shared.dataTask(with: request) { data, response, error in
			guard error == nil else {
				reject(error!)
				return
			}
			
			if let http = response as? HTTPURLResponse, http.statusCode != 200 {
				reject("HTTP \(http.statusCode)")
				return
			}
			
			guard let data = data else {
				reject("No Data")
				return
			}
			
			resolve(data)
		}
		.resume()
	}
}

final class PromiseLiteTests: XCTestCase {
	
	func wait(count: Int, timeout: TimeInterval = 1, name: String = #function, closure: ([XCTestExpectation]) -> Void) {
		var expectations = [XCTestExpectation]()
		
		for _ in 0..<count {
			let exp = expectation(description: name)
			expectations.append(exp)
		}
		
		closure(expectations)
		
		wait(for: expectations, timeout: timeout)
	}
	
	func wait(timeout: TimeInterval = 1, name: String = #function, closure: (XCTestExpectation) -> Void) {
		wait(count: 1, timeout: timeout, name: name) { expectations in
			closure(expectations[0])
		}
	}
	
	// Tests
	
	func testPromise_AutoRun() {
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
	
	func testPromise_Resolve() {
		wait { expectation in
			let promise = Promise.resolve(200)
			promise.then {
				XCTAssert($0 == 200)
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_Reject() {
		wait { expectation in
			let promise = Promise.reject("Some error")
			promise.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Some error")
				expectation.fulfill()
			}
		}
	}
	
    func testPromise_CreateOnMainQueue() {
		wait { expectation in
			Promise {
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectation.fulfill()
			}
		}
    }
	
	func testPromise_CreateOnGlobalQueue() {
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
	
	func testPromise_CreateOnThread() {
		wait { expectation in
			Thread.detachNewThreadSelector(#selector(thread), toTarget: self, with: expectation);
		}
    }
	
	func testPromise_RunOnQueues() {
		wait(count: 5) { expectations in
			Promise(.main) {
				XCTAssert(DispatchQueue.current == DispatchQueue.main)
				expectations[0].fulfill()
			}
			.then(.global()) { () -> Void in
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[1].fulfill()
			}
			.then(.global(qos: .utility)) { () -> Void in
				XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .utility))
				expectations[2].fulfill()
			}
			.then { () -> Void in
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectations[3].fulfill()
			}
			.then(.global(qos: .background)) {
				XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .background))
				expectations[4].fulfill()
			}
		}
	}
	
	func testPromise_ThrowNoCatch() {
		wait { expectation in
			expectation.isInverted = true
			
			Promise {
				throw "Some Error"
			}
			.then {
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_CatchThen() {
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
		
	func testPromise_ThrowCatch() {
		wait { expectation in
			Promise {
				throw "Some Error"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Some Error")
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_ThrowCatchThen() {
		wait { expectation in
			Promise {
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
	
	func testPromise_Rethrowing() {
		wait { expectation in
			Promise {
				throw "Some Error"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Some Error")
				throw "Other Error"
			}
			.then {
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Other Error")
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_AsyncCatch() {
		wait { expectation in
			Promise<Int> { resolve, reject in
				asyncAfter {
					reject("Error")
					// Skipped
					resolve(200)
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
	
	func testPromise_SyncThen() {
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
	
	func testPromise_AsyncThen() {
		wait { expectation in
			Promise<String> { resolve, reject in
				asyncAfter {
					resolve("Hello")
					
					// Skipped
					resolve("World")
					reject("Some Error")
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
	
	func testPromise_AsyncThenAsyncThen() {
		wait { expectation in
			Promise<String> { resolve, reject in
				asyncAfter {
					resolve("Hello")
				}
			}
			.then { str, resolve, reject in
				resolve(str.count)
			}
			.then {
				XCTAssert($0 == 5)
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_FinallyThen() {
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
	
	func testPromise_FinallyCatch() {
		wait(count: 3) { expectations in
			Promise<Int> { resolve, reject in
				asyncAfter {
					reject("Error")
					// Skipped
					resolve(200)
				}
			}
			.finally {
				expectations[0].fulfill()
			}
			.then { value in
				XCTFail()
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

	func testPromise_ThenSyncPromise() {
		wait { expectation in
			Promise {
				return 200
			}
			.then { value in
				Promise {
					value / 10
				}
			}
			.then {
				XCTAssert($0 == 20)
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_ThenAsyncPromise() {
		wait { expectation in
			Promise.resolve(200)
			.then { value in
				Promise { resolve, reject in
					asyncAfter {
						resolve(value / 10)
					}
				}
			}
			.then {
				XCTAssert($0 == 20)
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_All() {
		wait { expectation in
			Promise.all([
				Promise { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise { resolve, reject in
					asyncAfter(0.5) {
						resolve("World")
					}
				},
			] )
			.then { results in
				XCTAssert(results.count == 2)
				XCTAssert(results[0] == "Hello")
				XCTAssert(results[1] == "World")
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_AllAny() {
		wait { expectation in
			Promise.all([
				Promise<Any> { resolve, reject in
					asyncAfter {
						resolve("Hello")
					}
				},
				Promise.resolve(200)
			] )
			.then { results in
				XCTAssert(results.count == 2)
				XCTAssert(results[0] as! String == "Hello")
				XCTAssert(results[1] as! Int == 200)
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_AllCatch() {
		wait { expectation in
			Promise.all([
				Promise { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				},
				Promise.resolve(3),
			])
			.then { results in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_AllSettled() {
		wait { expectation in
			Promise.all(settled: true, [
				Promise<Any> { resolve, reject in
					asyncAfter {
						reject("Error")
					}
				},
				Promise.resolve(200),
				Promise.resolve(3.14)
			])
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
	
	func testPromise_RaceThen() {
		wait { expectation in
			Promise.race([
				Promise { resolve, reject in
					asyncAfter(1) {
						reject("Error")
					}
				},
				Promise { resolve, reject in
					asyncAfter {
						resolve(200)
					}
				}
			])
			.then { result in
				XCTAssert(result as! Int == 200)
				expectation.fulfill()
			}
			.catch { error in
				XCTFail()
			}
		}
	}
	
	func testPromise_RaceCatch() {
		wait { expectation in
			Promise.race([
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
			])
			.then { result in
				XCTFail()
			}
			.catch { error in
				XCTAssert(error.localizedDescription == "Error")
				expectation.fulfill()
			}
		}
	}
	
	func testPromise_Cancel() {
		wait { expectation in
			expectation.isInverted = true
		
			let p = Promise {
				expectation.fulfill()
			}
			p.cancel()
		}
	}
	
	func testPromise_CancelInside() {
		wait(count: 2) { expectations in
			expectations[1].isInverted = true
			
			let p = Promise {
				expectations[0].fulfill()
			}
			p.then {
				p.cancel()
			}
			.then {
				expectations[1].fulfill()
			}
		}
	}
	
	func testPromise_CancelAsync() {
		wait(count: 2) { expectations in
			expectations[1].isInverted = true
		
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
				expectations[1].fulfill()
			}
			.finally {
				expectations[1].fulfill()
			}
			
			asyncAfter(0.30) {
				p.cancel()
			}
		}
	}
	
	func testPromise_Suspend() {
		wait { expectation in
			expectation.isInverted = true
		
			Promise {
				expectation.fulfill()
			}
			.suspend()
		}
	}
	
	func testPromise_SuspendInside() {
		wait(count: 2) { expectations in
			expectations[1].isInverted = true
		
			let p = Promise {
				expectations[0].fulfill()
			}
			p.then {
				p.suspend()
			}
			.then {
				expectations[1].fulfill()
			}
		}
	}
	
	func testPromise_SuspendResume() {
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
			
			asyncAfter(0.3) {
				p.suspend()
			}
			
			asyncAfter(0.75) {
				p.resume()
			}
		}
	}
	
	func testPromise_Async() {
		wait { expectation in
			async<Int> {
				expectation.fulfill()
				return 200
			}
		}
	}
	
	func testPromise_AwaitSync() {
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
				print(error)
			}
		}
	}
	
	func testPromise_AwaitAsync() {
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
			.catch {
				print($0)
			}
		}
	}
	
	/// Load avatars of first 30 GitHub users
	func testPromise_SampleThen() {
		wait(timeout: 4) { expectation in
		
			fetch("https://api.github.com/users")
			.then { usersData in
				try JSONDecoder().decode([User].self, from: usersData)
			}
			.then { users -> Promise<Array<Data>> in
				guard users.count > 0 else {
					throw "Users list is empty"
				}
				return Promise.all(
					users
					.map { $0.avatar_url }
					.map { fetch($0) }
				)
			}
			.then { imagesData in
				imagesData.map { NSImage(data: $0) }
			}
			.then(.main) { images in
				XCTAssert(DispatchQueue.current == DispatchQueue.main)
				XCTAssert(images.count == 30)
				expectation.fulfill()
			}
			.catch { error in
				print("Error: \(error)")
			}
		}
	}
	
	func testPromise_SampleAwait() {
		wait(timeout: 4) { expectation in
		
			async {
				let usersData = try fetch("https://api.github.com/users").await()
				
				let users = try JSONDecoder().decode([User].self, from: usersData)
				guard users.count > 0 else {
					throw "Users list is empty"
				}
				
				let imagesData = try async.all(
					users
						.map { $0.avatar_url }
						.map { fetch($0) }
				).await()
				
				let images = imagesData.map { NSImage(data: $0) }
				
				async(.main) {
					XCTAssert(DispatchQueue.current == DispatchQueue.main)
					XCTAssert(images.count == 30)
					expectation.fulfill()
				}
			}
			.catch { error in
				print("Error: \(error)")
			}
		}
	}
}
