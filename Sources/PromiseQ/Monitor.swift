//
//  Monitor.swift
//
//  Created by Iurii Khvorost <iurii.khvorost@gmail.com> on 2020/05/14.
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

extension DispatchSemaphore {
	static func Lock() -> DispatchSemaphore {
		return DispatchSemaphore(value: 0)
	}
	
	static func Mutex() -> DispatchSemaphore {
		return DispatchSemaphore(value: 1)
	}
}

func synchronized<T : AnyObject, U>(_ obj: T, closure: () -> U) -> U {
	objc_sync_enter(obj)
	defer {
		objc_sync_exit(obj)
	}
	return closure()
}

@propertyWrapper
class Atomic<T> {
    private var value: T

    init(wrappedValue value: T) {
        self.value = value
    }

    var wrappedValue: T {
		get {
			synchronized(self) { value }
		}
		set {
			synchronized(self) { value = newValue }
		}
    }
}

class Monitor : Asyncable {
	@Atomic private var cancelled = false
	@Atomic var reject: (() -> Void)? {
		didSet {
			if self.cancelled {
				reject?()
			}
		}
	}
	@Atomic private var semaphore: DispatchSemaphore?
	@Atomic var task: Asyncable?
	
	var onDeinit: (() -> Void)?
	
	deinit {
		onDeinit?()
	}
	
	func cancel() {
		cancelled = true
		reject?()
		task?.cancel()
	}
	
	func suspend() {
		task?.suspend()
		
		if semaphore == nil {
			semaphore = .Lock()
		}
	}
	
	@discardableResult
	func wait() -> Bool {
		guard !cancelled else { return false }
		semaphore?.wait()
		return !cancelled
	}
	
	func resume() {
		task?.resume()
		
		semaphore?.signal()
		semaphore = nil
	}
}


struct AsyncContainer : Asyncable {
	@Atomic var tasks: [Asyncable]
	
	func suspend() {
		tasks.forEach { $0.suspend() }
	}
	
	func resume() {
		tasks.forEach { $0.resume() }
	}
	
	func cancel() {
		tasks.forEach { $0.cancel() }
	}
}
