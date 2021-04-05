//
//  PromiseQ.swift
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

private func setTimeout<T>(timeout: TimeInterval, pending: @escaping (Result<T, Error>) -> Void) {
	guard timeout > 0 else { return }
	let work = DispatchWorkItem {
		pending(.failure(PromiseError.timedOut))
	}
	DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout, execute: work)
}

private func pending<T>(monitor: Monitor, callback: @escaping (Result<T, Error>) -> Void) -> (Result<T, Error>) -> Void {
	var p = true
	return { [weak monitor] (result: Result<T, Error>) -> Void in
		if monitor != nil {
			synchronized(monitor!) {
				guard p else { return }
				p.toggle()
				callback(result)
			}
		}
	}
}

private func execute(_ queue: DispatchQueue, f: @escaping () -> Void) {
	if queue.label == String(cString: __dispatch_queue_get_label(nil)) {
		f()
	}
	else {
		queue.async(execute: f)
	}
}

private func retrySync(_ count: Int, monitor: Monitor?, do: () throws -> Void, catch: (Error) -> Void) {
	var r = count
	repeat {
		guard monitor == nil || monitor!.wait() else { return }
		
		r -= 1
		do {
			try `do`()
			r = -1
		}
		catch {
			if r < 0 {
				`catch`(error)
			}
		}
	} while r >= 0
}

private func retryAsync<T, U>(_ count: Int,
							  monitor: Monitor,
							  value: T,
							  pending: @escaping (Result<U, Error>) -> Void,
							  f: @escaping (T, @escaping (U) -> Void,  @escaping (Error) -> Void, inout Asyncable?) -> Void) {
	
	var r = count
	let lock = DispatchSemaphore.Lock()
	repeat {
		guard monitor.wait() else { return }
		
		r -= 1
		
		let rs = { (value: U) in
			r = -1
			lock.signal()
			monitor.task = nil
			
			pending(.success(value))
		}
		let rj = { (error: Error) in
			lock.signal()
			monitor.task = nil
			
			if r < 0 {
				pending(.failure(error))
			}
		}
		f(value, rs, rj, &monitor.task)
	
		lock.wait()
	}
	while r >= 0
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

/// Promise errors
public enum PromiseError: Error, LocalizedError {
	
	/// The Promise timed out.
	case timedOut

	/// All Promises rejected. See `Promise.any()`.
	case aggregate([Error])
	
	/// The Promise cancelled.
	case cancelled
	
	/// No Promises.
	case empty
	
	/// A localized message describing what error occurred.
	public var errorDescription: String? {
		switch self {
			case .timedOut:
				return "The Promise timed out."
			case .aggregate:
				return "All Promises rejected."
			case .cancelled:
				return "The Promise cancelled."
			case .empty:
				return "The Promises empty."
		}
	}
}

/// An asynchronous type that can suspend, resume and cancel it's execution.
///
/// The protocol is the base for asynchronous tasks then can be managed by promises.
public protocol Asyncable {
	
	/// Temporarily suspends a task.
	///
	/// A task, while suspended, produces no activity and is not subject to timeouts.
	func suspend()
	
	/// Resumes the task, if it is suspended.
	///
	/// If a task is in a suspended state, you need to call this method to start the task.
	func resume()
	
	/// Cancels the task.
	///
	/// This method returns immediately, marking the task as being canceled. This method may be called on a task that is suspended.
	func cancel()
}

/// Represents an asynchronous operation that can be chained.
public struct Promise<T> {
	
	private let f: (@escaping (Result<T, Error>) -> Void) -> Void
	private let autoRun: DispatchWorkItem
	private let monitor: Monitor
	
	/// Set deinit handler
	public func onDeinit(_ block: @escaping () -> Void) -> Void {
		monitor.onDeinit = block
	}
	
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
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that can return a value or throw an error.
	/// - Returns: A new `Promise`
	/// - SeeAlso: `Promise.resolve()`, `Promise.reject()`
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0, f: @escaping (() throws -> T)) {
		let monitor = Monitor()
		self.init(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			execute(queue) {
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				retrySync(retry, monitor: monitor,
					do: {
						let output = try f()
						p(.success(output))
					},
					catch: { error in
						p(.failure(error))
					}
				)
			}
		}
	}

	/// Initialize a new promise that can be resolved or rejected with the callbacks and can manage a wrapped asynchronous task.
	///
	/// The wrapped asynchronous task must be conformed to `Asyncable` protocol.
	///
	/// 	extension URLSessionDataTask: Asyncable {
	/// 	}
	///
	/// 	Promise { resolve, reject, task in
	///			task = URLSession.shared.dataTask(with: request) { data, response, error in
	///				guard error == nil else {
	///					reject(error!)
	///					return
	///				}
	///				resolve(data)
	///			}
	///			task.resume()
	///		}
	///
	/// - Parameters:
	/// 	- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that provides the callbacks to `resolve/reject` the promise and
	///		a wrapped asynchronous task to manage.
	/// - Returns: A new `Promise`
	/// - SeeAlso: `Asyncable`
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0, 
				f: @escaping (@escaping (T) -> Void,  @escaping (Error) -> Void, inout Asyncable?) -> Void) {
		let monitor = Monitor()
		self.init(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			execute(queue) {
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				retryAsync(retry,
						   monitor: monitor,
						   value: (),
						   pending: p,
						   f: { (v: Void, rs, rj, t) in f(rs, rj, &t) })
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
	/// The closure should call only one `resolve` or one `reject`. All further calls of resolve and reject are ignored:
	///
	/// 	Promise { resolve, reject in
	///			resolve("done")
	///			reject(error) // Ignored call
	///		}
	///
	/// - Parameters:
	/// 	- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that provides the callbacks to `resolve/reject` the promise
	/// - Returns: A new `Promise`
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0,  retry: Int = 0,
				f: @escaping ( @escaping (T) -> Void,  @escaping (Error) -> Void) -> Void) {
		self.init(queue, timeout: timeout, retry: retry) { resolve, reject, task in
			f(resolve, reject)
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
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that gets a result and can return a value or throw an error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0, f: @escaping ((T) throws -> U)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			self.f { result in
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				switch result {
					case let .success(input):
						execute(queue) {
							retrySync(retry, monitor: monitor,
								do: {
									let output = try f(input)
									p(.success(output))
								},
								catch: { error in
									p(.failure(error))
								}
							)
						}
					case let .failure(error):
						p(.failure(error))
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
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that gets a result and can return new promise or throw an error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0, f: @escaping ((T) throws -> Promise<U>)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			self.f { result in
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				switch result {
					case let .success(value):
						execute(queue) {
							retrySync(retry, monitor: monitor,
								  do: {
									let promise = try f(value)
									promise.autoRun.cancel()
									promise.f { result in
										switch result {
											case let .success(value):
												p(.success(value))
											
											case let .failure(error):
												p(.failure(error))
										}
									}
								},
								catch: { error in
									p(.failure(error))
								}
							)
						}
					case let .failure(error):
						p(.failure(error))
				}
			}
		}
	}
	
	///	The provided closure executes with a result of this promise when it is resolved and provides the callbacks to
	///	resolve or reject a chained promise and can manage a wrapped asynchronous task.
	///
	/// 	// The wrapped asynchronous task must be conformed to `Asyncable` protocol.
	/// 	extension URLSessionDataTask: Asyncable {
	/// 	}
	///
	/// 	let promise = Promise {
	///			return request
	///		}
	///		.then { request, resolve, reject, task in // `task` is in-out parameter
	/// 		task = URLSession.shared.dataTask(with: request) { data, response, error in
	/// 			guard error == nil else {
	/// 				reject(error!)
	/// 				return
	/// 			}
	/// 			resolve(data)
	/// 		}
	/// 		task.resume()
	/// 	}
	///
	/// 	// The promise and the data task will be suspended after 2 secs and won't produce any network activity.
	/// 	// but they can be resumed later.
	/// 	DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
	/// 		promise.suspend()
	/// 	}
	///
	///	- Parameters:
	///		- queue: The queue at which the closure should be executed. Defaults to `DispatchQueue.global()`.
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that gets a result and provides the callbacks to resolve or
	///		reject the promise and a wrapped asynchronous task to manage.
	///	- Returns: A new chained promise.
	/// - SeeAlso: `Asyncable`
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0,
						f: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void, inout Asyncable?) -> Void) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			self.f { result in
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				switch result {
					case let .success(value):
						execute(queue) {
							retryAsync(retry, monitor: self.monitor, value: value, pending: p, f: f)
						}
					case let .failure(error):
						p(.failure(error))
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
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that gets a result and provides the callbacks to resolve
	///		or reject the promise.
	///	- Returns: A new chained promise.
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0,
						f: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void) -> Void) -> Promise<U> {
		then(queue, timeout: timeout, retry: retry) { value, resolve, reject, task in
			f(value, resolve, reject)
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
	///		- timeout: The time interval to wait for resolving the promise.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	///		- f: The closure to be invoked on the queue that gets an error and can throw an other error.
	///	- Returns: A new chained promise.
	@discardableResult
	public func `catch`(_ queue: DispatchQueue = .global(), timeout: TimeInterval = 0, retry: Int = 0, f: @escaping ((Error) throws -> Void)) -> Promise<Void> {
		autoRun.cancel()
		return Promise<Void>(monitor) { callback in
			let p = pending(monitor: monitor, callback: callback)
			setTimeout(timeout: timeout, pending: p)
			self.f { result in
				monitor.reject = { p(.failure(PromiseError.cancelled)) }
				switch result {
					case .success:
						p(.success(()))
					case let .failure(error):
						execute(queue) {
							retrySync(retry, monitor: nil,
								do: {
									try f(error)
									p(.success(()))
								},
								catch: { error in
									p(.failure(error))
								}
							)
						}
				}
			}
		}
	}
	
	/// The provided closure always runs when the promise is settled: be it resolve or reject.
	///
	/// It is a good handler for performing cleanup, e.g. stopping loading indicators, as they are not needed anymore,
	/// no matter what the outcome is. That’s very convenient, because finally is not meant to process the promise's result.
	/// So it passes it through.
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
			self.f { result in
				monitor.wait()
				execute(queue, f: f)
				switch result {
					case let .success(value):
						callback(.success(value))
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
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
	/// The method is used for compatibility, when a function is expected to return the promise.
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
	
	/// Creates a rejected promise with a given error.
	///
	/// 	Promise {
	///		    throw error
	///		}
	///
	///		// Same as above
	///		Promise<Void>.rejected(error)
	///
	///	- Parameter error: The error of the rejected promise.
	///	- Returns: A new rejected promise
	public static func reject(_ error: Error) -> Promise<T> {
		return Promise { () -> T in throw error }
	}
	
	/// Executes all promises in parallel and returns a single promise that resolves when all of the promises have been
	/// resolved or settled and returns an array of their results.
	///
	/// If `settled=false` the new promise resolves when all listed promises are resolved, and the array of their results
	/// becomes its result. If any of the promises is rejected, the promise returned by `Promise.all` immediately rejects
	/// with that error.
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
		promises.forEach { $0.autoRun.cancel() }
		let container = AsyncContainer(tasks: promises.map(\.monitor))
		
		return Promise<Array<T>> { resolve, reject, task in
			
			guard promises.count > 0 else {
				resolve([T]())
				return
			}
			
			task = container
			
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
					if settled, let value = error as? T {
						setResult(i, value: value)
					}
					else {
						reject(error)
					}
				}
			}
		}
	}
	
	/// Executes all promises in parallel and returns a single promise that resolves when all of the promises have been
	/// resolved or settled and returns an array of their results.
	///
	/// For more details see:
	///
	///		Promise.all(settled, [Promise<T>]) -> Promise<Array<T>>
	///
	public static func all(settled: Bool = false, _ promises: Promise<T>...) -> Promise<Array<T>> {
		return all(settled: settled, promises)
	}
	
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
		promises.forEach { $0.autoRun.cancel() }
		let container = AsyncContainer(tasks: promises.map(\.monitor))
		return Promise { resolve, reject, task in
			
			guard promises.count > 0 else {
				reject(PromiseError.empty)
				return
			}
			
			task = container
			
			promises.forEach {
				$0.then { resolve($0) }
				.catch { reject($0) }
			}
		}
	}
	
	/// Waits only for the first settled promise and gets its result (or error).
	///
	/// For more details see:
	///
	/// 	Promise.race([Promise<T>]) -> Promise<T>
	///
	/// - SeeAlso: Promise.race([Promise<T>]) -> Promise<T>
	public static func race(_ promises:Promise<T>...) -> Promise<T> {
		return race(promises)
	}
	
	/// Waits only for the first fulfilled promise and gets its result.
	///
	///		Promise.any(
	///			Promise { resolve, reject in
	///				reject("Error")
	///			},
	///			Promise { resolve, reject in
	///				DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///					resolve(200)
	///				}
	///			}
	///		)
	///		.then {
	///			print($0)
	///		}
	///		// Prints "200"
	///
	/// If all of the given promises are rejected,
	/// then the returned promise is rejected with `PromiseError.aggregate` that stores all promise errors.
	///
	///		Promise.any(
	///			Promise { resolve, reject in
	///				reject("Error")
	///			},
	///			Promise { resolve, reject in
	///				DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
	///					reject("Fail")
	///			 	}
	///		 	}
	///	 	)
	///	 	.catch { error in
	///			if case let PromiseError.aggregate(errors) = error {
	///				print(errors)
	///		 	}
	///	 	}
	///	 	// Prints '["Error", "Fail"]'
	///
	///	- Parameter promises: An array of promises to execute.
	///	- Returns: A new single promise.
	/// - SeeAlso: `Promise.race()`
	public static func any(_ promises:[Promise<T>]) -> Promise<T> {
		var errors = [Int : Error]()
		let mutex = DispatchSemaphore.Mutex()
		promises.forEach { $0.autoRun.cancel() }
		let container = AsyncContainer(tasks: promises.map(\.monitor))
		
		return Promise<T> { resolve, reject, task in
			
			guard promises.count > 0 else {
				reject(PromiseError.empty)
				return
			}
			
			task = container
			
			func setError(_ i: Int, error: Error) {
				mutex.wait()
				defer {
					mutex.signal()
				}

				errors[i] = error
				if errors.count == promises.count {
					let errors = errors.keys.sorted().map { errors[$0]! }
					reject(PromiseError.aggregate(errors))
				}
			}

			for i in 0..<promises.count {
				promises[i].then { resolve($0) }
				.catch {
					setError(i, error: $0)
				}
			}
		}
	}

	/// Waits only for the first fulfilled promise and gets its result. If all of the given promises are rejected,
	/// then the returned promise is rejected with `PromiseError.aggregate` that stores all promise errors.
	///
	/// For more details see:
	///
	/// 	Promise.any([Promise<T>]) -> Promise<T>
	///
	/// - SeeAlso: Promise.any([Promise<T>]) -> Promise<T>
	public static func any(_ promises: Promise<T>...) -> Promise<T> {
		return any(promises)
	}
	
}

extension Promise : Asyncable {
	/// Suspends the promise or the promise chain.
	///
	/// Suspension does not affect the execution of the promise that has already begun it stops execution of next
	/// promises in a chain. Call `resume()` to continue executing the promise or the promise chain.
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
		monitor.suspend()
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
		monitor.resume()
	}
	
	/// Cancels execution of the promise or the promise chain.
	///
	///		let p = Promise {
	///     	return 200 // Doesn't execute
	///     }
	///     p.cancel()
	///
	/// Cancelation does not affect the execution of the promise that has already begun it cancels execution of next
	/// promises in the chain.
	public func cancel() {
		monitor.cancel()
	}
}

