//
// PromiseQ
// Copyright 2020 Iurii Khvorost <iurii.khvorost@gmail.com>. All rights reserved.
//

import Foundation

private class Semaphore {
	var cancelled = false
	var semaphore: DispatchSemaphore?
}

public struct Promise<T> {
	
	private typealias Callback = (Result<T, Error>) -> Void
	
	private let f: (@escaping Callback) -> Void
	private let autoRun: DispatchWorkItem
	private var semaphore: Semaphore
	
	private init(_ semaphore: Semaphore, f: @escaping (@escaping Callback) -> Void) {
		self.f = f
		self.autoRun = DispatchWorkItem { f { _ in } }
		self.semaphore = semaphore
		
		DispatchQueue.global().asyncAfter(deadline: .now() + 0.01, execute: self.autoRun)
	}
	
	@discardableResult
	public init(_ queue: DispatchQueue = .global(), f: @escaping (() throws -> T)) {
		self.init(Semaphore()) { callback in
			queue.async {
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

	@discardableResult
	public init(_ queue: DispatchQueue = .global(), f: @escaping ( @escaping (T) -> Void,  @escaping (Error) -> Void) -> Void) {
		self.init(Semaphore()) { callback in
			queue.async {
				var pending = true
				f({ value in // resolve
					guard pending else { return }
					pending.toggle()
					callback(.success(value))
				  },
				  { error in // reject
					guard pending else { return }
					pending.toggle()
					callback(.failure(error))
				})
			}
		}
	}
	
	private func exec(_ queue: DispatchQueue, f: @escaping () -> Void) {
		guard !semaphore.cancelled else {
			return
		}
		
		semaphore.semaphore?.wait()
		
		guard !semaphore.cancelled else {
			return
		}
		
		if queue.label == String(cString: __dispatch_queue_get_label(nil)) {
			f()
		}
		else {
			queue.async(execute: f)
		}
	}
	
	public func suspend() {
		guard semaphore.semaphore == nil else {
			return
		}
		semaphore.semaphore = DispatchSemaphore(value: 0)
	}
	
	public func resume() {
		semaphore.semaphore?.signal()
		semaphore.semaphore = nil
	}
	
	public func cancel() {
		autoRun.cancel()
		semaphore.cancelled = true
	}
	
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), f: @escaping ((T) throws -> U)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(semaphore) { callback in
			self.f { result in
				switch result {
					case let .success(input):
						self.exec(queue) {
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
	
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), f: @escaping ((T) throws -> Promise<U>)) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(semaphore) { callback in
			self.f { result in
				switch result {
					case let .success(value):
						self.exec(queue) {
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
	
	@discardableResult
	public func then<U>(_ queue: DispatchQueue = .global(), f: @escaping (T, @escaping (U) -> Void, @escaping (Error) -> Void) -> Void) -> Promise<U> {
		autoRun.cancel()
		return Promise<U>(semaphore) { callback in
			self.f { result in
				switch result {
					case let .success(value):
						self.exec(queue) {
							var pending = true
							f(value,
							  { value in // resolve
								guard pending else { return }
								pending.toggle()
								callback(.success(value))
							  },
							  { error in // reject
								guard pending else { return }
								pending.toggle()
								callback(.failure(error))
							  }
							)
						}
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
	
	@discardableResult
	public func `catch`(_ queue: DispatchQueue = .global(), f: @escaping ((Error) throws -> Void)) -> Promise<Void> {
		autoRun.cancel()
		return Promise<Void>(semaphore) { callback in
			self.f { result in
				switch result {
					case .success:
						callback(.success(()))
					case let .failure(error):
						self.exec(queue) {
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
	
	@discardableResult
	public func finally(_ queue: DispatchQueue = .global(), f: @escaping (() -> Void)) -> Promise<T> {
		autoRun.cancel()
		return Promise<T>(semaphore) { callback in
			self.f { result in
				self.exec(queue, f: f)
				
				switch result {
					case let .success(value):
						callback(.success(value))
					case let .failure(error):
						callback(.failure(error))
				}
			}
		}
	}
}

extension Promise {
	
	public static func resolve(_ value: T) -> Promise<T> {
		return Promise<T> { return value }
	}
}

extension Promise where T == Void {
	
	public static func reject(_ error: Error) -> Promise<T> {
		return Promise<T> { throw error }
	}
	
}

extension Promise {
	
	public static func all(settled: Bool = false, _ promises:[Promise<T>]) -> Promise<Array<T>> {
		var results = Array<T>()
		
		var p = Promise<Void> { }
		promises.forEach { item in
			p = p.then {
				item.then { results.append($0) }
			}
			
			if settled, T.self == Any.self {
				p = p.catch { results.append($0 as! T) }
			}
		}
		
		return p.then {
			return results
		}
	}
	
}

extension Promise where T == Any {
	
	public static func race(_ promises:[Promise<T>]) -> Promise<T> {
		return Promise { resolve, reject in
			promises.forEach {
				$0.then { resolve($0) }
				.catch { reject($0) }
			}
		}
	}
}

