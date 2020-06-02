//
//  PromiseQ
//
//  Created by Iurii Khvorost <iurii.khvorost@gmail.com> on 2020/04/01.
//  Copyright © 2020 Iurii Khvorost. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import Foundation

private func setTimeout<T>(timeout: TimeInterval, callback: @escaping (Result<T, Error>) -> Void) {
	guard timeout > 0 else { return }
	let workItem = DispatchWorkItem { callback(.failure(PromiseError.timedOut)) }
	DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: workItem)
}

private func isPending(_ pending: inout Bool) -> Bool {
	guard pending else { return false}
	pending.toggle()
	return true
}

private func execute(_ queue: DispatchQueue, monitor: Monitor, f: @escaping () -> Void) {
	guard !monitor.isCancelled else {
		return
	}
	
	monitor.wait()
	
	guard !monitor.isCancelled else {
		return
	}
	
	if queue.label == String(cString: __dispatch_queue_get_label(nil)) {
		f()
	}
	else {
		queue.async(execute: f)
	}
}

/// Alias for Promise.
///
/// The alias is used for `async/await` notation.
///
/// 	Promise {
///		    return 200
///		}
///		.then { value in
///		    print(value)
///		}
///		// Prints "200"
///
///		// Same as above
/// 	async {
/// 	    let value = try async { return 200 }.await()
/// 	    print(value)
///		}
///
/// - SeeAlso: `Promise.await()`.
public typealias async = Promise

public enum PromiseError: String, LocalizedError {
	case timedOut = "The promise timed out."
	public var errorDescription: String? { return rawValue }
}

/// Represents an asynchronous operation that can be chained.
public struct Promise<T> {
	
	private let f: (@escaping (Result<T, Error>) -> Void) -> Void
	private let autoRun: DispatchWorkItem
	private let monitor: Monitor
	
	private init(_ monitor: Monitor, f: @escaping (@escaping (Result<T, Error>) -> Void) -> Void) {
		self.f = f
		self.monitor = monitor
		
		self.autoRun = DispatchWorkItem { f { _ in } }
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.01, execute: self.autoRun)
	}
	
	/// Initialize a new promise that can be resolved or rejected with the closure.
	///
	/// When new promise is created, the closure runs automatically.
	///
	///		// Resolved promise
	///     Promise {
	///        return 200
	///     }
	///
	/// 	// Rejected promise on the main queue
	///     Promise(.main) {
	///		    throw error
	///     }
	///
	/// - Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that can return a value or throw an error.
	/// - Returns: A new `Promise`
	/// - SeeAlso: `Promise.resolve()`, `Promise.reject()`
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping (() throws -> T)) {
		let monitor = Monitor()
		self.init(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			execute(queue, monitor: monitor) {
				do {
					let output = try f()
					callback(.success(output))
				}
				catch {
					callback(.failure(error))
				}
			}
		}
	}

	/// Initialize a new promise that can be resolved or rejected with the callbacks.
	///
	/// When new promise is created, the closure runs automatically.
	///
	///		// Resolved promise
	///     Promise { resolve, reject in
	///     	resolve(200)
	///     }
	///
	/// 	// Rejected promise on the main queue
	///     Promise(.main) { resolve, reject in
	///			reject(error)
	///     }
	///
	/// The closure should call only one resolve or one reject. All further calls of resolve and reject are ignored:
	///
	/// 	Promise { resolve, reject in
	///			resolve("done")
	///			reject(error) // ignored
	///		}
	///
	/// - Parameters:
	/// 	- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that provides the callbacks to resolve or reject the promise.
	/// - Returns: A new `Promise`
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping ( @escaping (T) -> Void,  @escaping (Error) -> Void) -> Void) {
		let monitor = Monitor()
		self.init(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			execute(queue, monitor: monitor) {
				f( { value in callback(.success(value))}, { error in callback(.failure(error))} )
			}
		}
	}
	
	///	The provided closure executes with a result of this promise when it is resolved.
	///
	///	This allows chaining promises and passes results through the chain.
	///
	///		Promise {
	///			return 200
	///		}
	///		.then { value -> Int in
	///			print(value) // Prints "200"
	///			return value / 10
	///		}
	///		.then {
	///			print($0) // Prints "20"
	///		}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that gets a result and can return a value or throw an error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping ((T) throws -> U)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			var pending = true
			self.f { result in
				guard isPending(&pending) else { return }
				switch result {
					case let .success(input):
						execute(queue, monitor: self.monitor) {
							do {
								let output = try f(input)
								callback(.success(output))
							}
							catch {
								callback(.failure(error))
							}
						}
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
	
	///	The provided closure executes with a result of this promise when it is resolved.
	///
	///	This allows chaining promises and passes results through the chain.
	///
	///		Promise {
	///			return 200
	///		}
	///		.then { value in
	///			Promise {
	///				value / 10
	///			}
	///		}
	///		.then {
	///			XCTAssert($0 == 20)
	///			exp.fulfill()
	///		}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that gets a result and can return new promise or throw an error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping ((T) throws -> Promise<U>)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			var pending = true
			self.f { result in
				guard isPending(&pending) else { return }
				switch result {
					case let .success(value):
						execute(queue, monitor: self.monitor) {
							do {
								let promise = try f(value)
								promise.autoRun.cancel()
								promise.f { result in
									switch result {
										case let .success(value):
											callback(.success(value))
										
										case let .failure(error):
											callback(.failure(error))
									}
								}
							}
							catch {
								callback(.failure(error))
							}
						}
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
	
	///	The provided closure executes with a result of this promise when it is resolved.
	///
	///	This allows chaining promises and passes results through the chain.
	///
	///		Promise {
	///			return "done"
	///		}
	///		.then { value, resolve, reject in
	///			resolve(value.count)
	///		}
	///		.then {
	///			print($0) // Prints "4"
	///		}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that gets a result and provides the callbacks to resolve or reject the promise.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void) -> Void) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			var pending = true
			self.f { result in
				guard isPending(&pending) else { return }
				switch result {
					case let .success(value):
						execute(queue, monitor: self.monitor) {
							f(value, { value in callback(.success(value)) }, { error in callback(.failure(error)) })
						}
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
	
	/// The provided closure executes when any promise in the promise chain is rejected.
	///
	/// 	Promise {
	/// 		try String(contentsOfFile: "none")
	/// 	}
	/// 	.then {
	/// 		print($0) // Doesn't execute
	/// 	}
	/// 	.catch { error in
	/// 		print(error.localizedDescription) // Prints "The file “none” couldn’t be opened because there is no such file."
	/// 	}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving a promise.
	///		- f: The closure to be invoked on the queue that gets an error and can throw an other error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func `catch`(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, f: @escaping ((Error) throws -> Void)) -> Promise<Void> {
		autoRun.cancel()
		return Promise<Void>(monitor) { callback in
			setTimeout(timeout: timeout, callback: callback)
			var pending = true
			self.f { result in
				guard isPending(&pending) else { return }
				switch result {
					case .success:
						callback(.success(()))
					case let .failure(error):
						execute(queue, monitor: self.monitor) {
							do {
								try f(error)
								callback(.success(()))
							}
							catch {
								callback(.failure(error))
							}
						}
				}
			}
		}
	}
	
	/// The provided closure always runs when the promise is settled: be it resolve or reject.
	///
	/// It is a good handler for performing cleanup, e.g. stopping loading indicators, as they are not needed anymore, no matter what the outcome is. That’s very convenient, because finally is not meant to process a promise result. So it passes it through.
	///
	/// The result is passed from `finally` to `then`:
	///
	///  	Promise {
	///		    return 200
	///		}
	///		.finally {
	///		    print("Promise is settled") // Prints "Promise is settled"
	///		}
	///		.then { value in
	///		    print(value) // Prints "200"
	///		}
	///		.finally {
	///		    print("Finish") // Prints "Finish"
	///		}
	///
	/// The error is passed from `finally` to `catch`:
	///
	///		Promise {
	///			try String(contentsOfFile: "none")
	///		}
	///		.finally {
	///			print("Promise is settled") // Prints "Promise is settled"
	///		}
	///		.then { value in
	///			print(value) // Doesn't execute
	///		}
	///		.catch { error in
	///			print(error.localizedDescription) // Prints "The file “none” couldn’t be opened because there is no such file."
	///		}
	///		.finally {
	///			print("Finish") // Prints "Finish"
	///		}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- f: The closure to be invoked on the queue that gets an error and can throw an other error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func finally(_ queue: DispatchQueue = .global(), f: @escaping (() -> Void)) -> Promise<T> {
		autoRun.cancel()
		return Promise<T>(monitor) { callback in
			var pending = true
			self.f { result in
				guard isPending(&pending) else { return }
				execute(queue, monitor: self.monitor, f: f)
				switch result {
					case let .success(value):
						callback(.success(value))
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
	
	/// Suspends the promise or the promise chain.
	///
	/// Suspension does not affect the execution of the promise that has already begun it stops execution of next promises in a chain. Call `resume()` to continue executing the promise or the promise chain.
	///
	///		// Suspended promise
	///		Promise {
	///			// Runs after `resume()` only
	///     	return 200
	///     }
	///     .suspend()
	///
	///		// Suspend next promise in a promise chain
	///		let p = Promise {
	///     	return 200
	///     }
	///     p.then {
	///			p.suspend()
	///		}
	///		.then {
	///			// Runs after `resume()` only
	///		}
	///
	/// - SeeAlso: `resume()`
	public func suspend() {
		monitor.lock()
	}
	
	/// Resumes the promise or the promise chain.
	///
	/// Resume continues executing the promise or the promise chain.
	///
	///		// Suspended promise
	///		let p = Promise {
	///			// Runs after `resume()` only
	///     	return 200
	///     }
	///     p.suspend()
	///
	///		// Resume the promise after 1 sec
	///		DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///			p.resume()
	///		}
	///
	/// - SeeAlso: `suspend()`
	public func resume() {
		monitor.unlock()
	}
	
	/// Cancels execution of the promise or the promise chain.
	///
	///		let p = Promise {
	///     	return 200 // Doesn't execute
	///     }
	///     p.cancel()
	///
	/// Cancelation does not affect the execution of the promise that has already begun it cancels execution of next promises in the chain.
	public func cancel() {
		monitor.cancel()
	}
	
	/// Returns a result of the promise synchronously or throws an error.
	///
	/// It blocks the current execution queue and waits for a result or an error:
	///
	///		do {
	///		    let text = try Promise { try String(contentsOfFile: file) }.await()
	///		    print(text)
	///		}
	///		catch {
	///		    print(error)
	///		}
	///
	///	Use `async/await` notation to work asynchronously:
	///
	///		async {
	///		    let text = try async { try String(contentsOfFile: file) }.await()
	///		    print(text)
	///		}
	///		.catch {
	///		    print($0)
	///		}
	///
	///	- Returns: A result of the promise.
	/// - SeeAlso: async.
	public func await() throws -> T {
		var result: T?
		var error: Error?
		let lock = DispatchSemaphore.Lock()
		
		self.then {
			result = $0
			lock.signal()
		}
		.catch {
			error = $0
			lock.signal()
		}
		
		lock.wait()
		
		if let e = error {
			throw e
		}
		
		return result!
	}
	
	/// Creates a resolved promise with a given value.
	///
	/// The method is used for compatibility, when a function is expected to return a promise.
	///
	/// 	Promise {
	///		    return 200
	///		}
	///
	///		// Same as above
	/// 	Promise.resolve(200)
	///
	///	- Parameter value: The result of the resolved promise.
	///	- Returns: A new resolved promise
	public static func resolve(_ value: T) -> Promise<T> {
		return Promise<T> { return value }
	}
	
	/// Executes all promises in parallel and returns a single promise that resolves when all of the promises have been resolved or settled and returns an array of their results.
	///
	/// If `settled=false` the new promise resolves when all listed promises are resolved, and the array of their results becomes its result. If any of the promises is rejected, the promise returned by `Promise.all` immediately rejects with that error.
	///
	/// 	Promise.all([
	/// 	    Promise {
	/// 	        return "Hello"
	/// 	    },
	/// 	    Promise { resolve, reject in
	///		        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///                 resolve("World")
	/// 	        }
	/// 	    }
	/// 	])
	/// 	.then { results in
	/// 	    print(results)
	/// 	}
	/// 	// Prints ["Hello", "World"]
	///
	/// If `settled=true` the new promise resolves when all listed promises are settled regardless of the result.
	///
	/// 	Promise.all(settled: true, [
	/// 	    Promise<Any> { resolve, reject in
	/// 	        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///		            reject(error)
	/// 	        }
	/// 	    },
	/// 	    Promise {
	/// 	        return 200
	/// 	    },
	/// 	])
	///		.then { results in
	///		    print(results)
	///		}
	///		// Prints [error, 200]
	///
	///	- Parameters:
	///		- settled: Defaults to `false`.
	///		- promises: An array of promises.
	///	- Returns: A new single promise.
	/// - SeeAlso: `Promise.race()`
	public static func all(settled: Bool = false, _ promises:[Promise<T>]) -> Promise<Array<T>> {
		var results = [Int : T]()
		let mutex = DispatchSemaphore.Mutex()
		
		return Promise<Array<T>> { resolve, reject in
			
			func setResult(_ i: Int, value: T) {
				mutex.wait()
				defer {
					mutex.signal()
				}
				
				results[i] = value
				if results.count == promises.count {
					let values = results.keys.sorted().map { results[$0]! }
					resolve(values)
				}
			}
			
			for i in 0..<promises.count {
				promises[i].then {
					setResult(i, value: $0)
				}
				.catch { error in
					if settled , let value = error as? T {
						setResult(i, value: value)
					}
					else {
						reject(error)
					}
				}
			}
		}
	}
	
}

extension Promise where T == Void {
	
	/// Creates a rejected promise with a given error.
	///
	/// 	Promise {
	///		    throw error
	///		}
	///
	///		// Same as above
	///		Promise.rejected(error)
	///
	///	- Parameter error: The error of the rejected promise.
	///	- Returns: A new rejected promise
	public static func reject(_ error: Error) -> Promise<Void> {
		return Promise<Void> { () -> Void in throw error }
	}
}

extension Promise where T == Any {
	
	/// Waits only for the first settled promise and gets its result (or error).
	///
	/// 	Promise.race([
	///			Promise { resolve, reject in
	///				DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
	///					reject("Error")
	///				}
	///			},
	///			Promise { resolve, reject in
	///				DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///					resolve(200)
	///				}
	///			}
	///		])
	///		.then {
	///			print($0)
	///		}
	///		// Prints "200"
	///
	///	- Parameter promises: An array of promises to execute.
	///	- Returns: A new single promise.
	/// - SeeAlso: `Promise.all()`
	public static func race(_ promises:[Promise<T>]) -> Promise<T> {
		return Promise { resolve, reject in
			promises.forEach {
				$0.then { resolve($0) }
				.catch { reject($0) }
			}
		}
	}
}

