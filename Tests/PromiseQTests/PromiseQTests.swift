
import XCTest
@testable import PromiseQ

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

final class PromiseLiteTests: XCTestCase {
	
	func expect(inverted: Bool = false, name: String = #function) -> XCTestExpectation {
		let exp = expectation(description: name);
		exp.isInverted = inverted
		return exp
	}
	
	func wait(_ expectation: XCTestExpectation, timeout: TimeInterval = 1) {
		wait(for: [expectation], timeout: timeout)
	}
	
	func waitAll(_ expectations: [XCTestExpectation], timeout: TimeInterval = 1) {
		wait(for: expectations, timeout: timeout)
	}
	
	// Tests
	
	func testPromise_AutoRun() {
		let exp1 = expect()
		let exp2 = expect()
		
		Promise {
			exp1.fulfill()
		}
		
		Promise<Void> { resolve, reject in
			exp2.fulfill()
		}
		
		waitAll([exp1, exp2])
	}
	
	func testPromise_Resolve() {
		let exp = expect()
		
		let promise = Promise.resolve(200)
		
		promise.then {
			XCTAssert($0 == 200)
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_Reject() {
		let exp = expect()
		
		let promise = Promise.reject("Some error")
		
		promise.then {
			XCTFail()
		}
		.catch { error in
			XCTAssert(error.localizedDescription == "Some error")
			exp.fulfill()
		}
		
		wait(exp)
	}
	
    func testPromise_CreateOnMainQueue() {
		let expectation = expect()
		
		Promise {
			XCTAssert(DispatchQueue.current == DispatchQueue.global())
			expectation.fulfill()
		}
		
		wait(expectation)
    }
	
	func testPromise_CreateOnGlobalQueue() {
		
		let expectation = expect()
		
		DispatchQueue.global().async {
			Promise {
				XCTAssert(DispatchQueue.current == DispatchQueue.global())
				expectation.fulfill()
			}
		}
		
		wait(expectation)
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
		let expectation = expect()
		
		Thread.detachNewThreadSelector(#selector(thread), toTarget: self, with: expectation);
		
		wait(expectation)
    }
	
	func testPromise_RunOnQueues() {
		let exp1 = expect()
		let exp2 = expect()
		let exp3 = expect()
		let exp4 = expect()
		let exp5 = expect()
		
		Promise(.main) {
			XCTAssert(DispatchQueue.current == DispatchQueue.main)
			exp1.fulfill()
		}
		.then(.global()) { () -> Void in
			XCTAssert(DispatchQueue.current == DispatchQueue.global())
			exp2.fulfill()
		}
		.then(.global(qos: .utility)) { () -> Void in
			XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .utility))
			exp3.fulfill()
		}
		.then { () -> Void in
			XCTAssert(DispatchQueue.current == DispatchQueue.global())
			exp4.fulfill()
		}
		.then(.global(qos: .background)) {
			XCTAssert(DispatchQueue.current == DispatchQueue.global(qos: .background))
			exp5.fulfill()
		}
		
		waitAll([exp1, exp2, exp3, exp4, exp5])
	}
	
	func testPromise_ThrowNoCatch() {
		let exp = expect(inverted: true)
		
		Promise {
			throw "Some Error"
		}
		.then {
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_CatchThen() {
		let expectation = expect()
		
		Promise {
			return 100
		}
		.catch { error in
			XCTFail()
		}
		.then {
			expectation.fulfill()
		}
		
		wait(expectation)
	}
		
	func testPromise_ThrowCatch() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_ThrowCatchThen() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_Rethrowing() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_AsyncCatch() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_SyncThen() {
		let expectation = expect()
		
		Promise {
			return "Hello"
		}
		.then {
			XCTAssert($0 == "Hello")
			expectation.fulfill()
		}
		
		wait(expectation)
	}
	
	func testPromise_AsyncThen() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_AsyncThenAsyncThen() {
		let expectation = expect()
		
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
		
		wait(expectation)
	}
	
	func testPromise_FinallyThen() {
		let exp1 = expect()
		let exp2 = expect()
		let exp3 = expect()
		
		Promise {
			return 100
		}
		.finally {
			exp1.fulfill()
		}
		.then { value in
			XCTAssert(value == 100)
				exp2.fulfill()
		}
		.finally {
			exp3.fulfill()
		}
		
		waitAll([exp1, exp2, exp3])
	}
	
	func testPromise_FinallyCatch() {
		let exp1 = expect()
		let exp2 = expect()
		let exp3 = expect()
		
		Promise<Int> { resolve, reject in
			asyncAfter {
				reject("Error")
				// Skipped
				resolve(200)
			}
		}
		.finally {
			exp1.fulfill()
		}
		.then { value in
			XCTFail()
		}
		.catch { error in
			XCTAssert(error.localizedDescription == "Error")
			exp2.fulfill()
		}
		.finally {
			exp3.fulfill()
		}
		
		waitAll([exp1, exp2, exp3])
	}

	func testPromise_ThenSyncPromise() {
		let exp = expect()
		
		Promise {
			return 100
		}
		.then { value in
			Promise {
				value / 10
			}
		}
		.then {
			XCTAssert($0 == 10)
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_ThenAsyncPromise() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_All() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_AllAny() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_AllCatch() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_AllSettled() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		.catch { error in
			XCTFail()
		}
		
		wait(exp)
	}
	
	func testPromise_RaceThen() {
		let exp = expect()
		
		Promise.race([
			Promise { resolve, reject in
				asyncAfter(1) {
					reject("Error")
				}
			},
			Promise { resolve, reject in
				asyncAfter {
					resolve(3)
				}
			}
		])
		.then { result in
			XCTAssert(result as! Int == 3)
			exp.fulfill()
		}
		.catch { error in
			XCTFail()
		}
		
		wait(exp)
	}
	
	func testPromise_RaceCatch() {
		let exp = expect()
		
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
			exp.fulfill()
		}
		
		wait(exp)
	}
	
	func testPromise_Cancel() {
		let exp = expect(inverted: true)
		
		let p = Promise {
			exp.fulfill()
		}
		p.cancel()
		
		wait(exp)
	}

	func testPromise_CancelSync() {
		let exp1 = expect()
		let exp2 = expect(inverted: true)
		
		let p = Promise.resolve(200)
		p.then { (value:Int) -> Void in
			XCTAssert(value == 200)
			exp1.fulfill()
			
			p.cancel() // Cancel the promise
		}
		.then {
			exp2.fulfill()
		}
		.finally {
			exp2.fulfill()
		}
		
		waitAll([exp1, exp2])
	}
	
	func testPromise_CancelAsync() {
		let exp1 = expect()
		let exp2 = expect(inverted: true)
		
		let p = Promise { resolve, reject in
			asyncAfter {
				resolve(200)
			}
		}
		.then { value, resolve, reject in
			XCTAssert(value == 200)
			exp1.fulfill()
			
			asyncAfter {
				resolve(())
			}
		}
		.then {
			exp2.fulfill()
		}
		.finally {
			exp2.fulfill()
		}
		
		asyncAfter(0.30) {
			p.cancel()
		}
		
		waitAll([exp1, exp2])
	}
	
	func testPromise_Suspend() {
		let exp = expect()
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
			exp.fulfill()
		}
		
		asyncAfter(0.3) {
			p.suspend()
		}
		
		asyncAfter(0.75) {
			p.resume()
		}
		
		wait(exp)
	}
	
	/// Load avatars of first 30 GitHub users
	func testPromise_Sample() {
		let exp = expect()
		
		struct User : Codable {
			let login: String
			let avatar_url: String
		}
		
		func fetch(_ path: String) -> Promise<Data> {
			Promise<Data> { resolve, reject in
				guard let url = URL(string: path) else {
					reject("Bad path")
					return
				}
				
				var request = URLRequest(url: url)
				
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
						reject("HTTP \(http.statusCode) - \(http.allHeaderFields.description)")
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
		
		fetch("https://api.github.com/users")
		.then { data in
			try JSONDecoder().decode([User].self, from: data)
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
		.then { results in
			results.map { NSImage(data: $0) }
		}
		.then(.main) { images in
			XCTAssert(DispatchQueue.current == DispatchQueue.main)
			XCTAssert(images.count == 30)
			exp.fulfill()
		}
		.catch { error in
			print("Error: \(error)")
			exp.fulfill()
		}
		
		wait(exp, timeout: 4)
	}
}
