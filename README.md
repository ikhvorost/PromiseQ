# PromiseQ

[![Language: Swift](https://img.shields.io/badge/language-swift-f48041.svg?style=flat)](https://developer.apple.com/swift)
![Platform: iOS 8+/macOS10.11](https://img.shields.io/badge/platform-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS%20|%20Linux-blue.svg?style=flat)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Build Status](https://travis-ci.org/ikhvorost/PromiseQ.svg?branch=master)](https://travis-ci.org/ikhvorost/PromiseQ)
[![codecov](https://codecov.io/gh/ikhvorost/PromiseQ/branch/master/graph/badge.svg)](https://codecov.io/gh/ikhvorost/PromiseQ)

Fast, powerful and lightweight implementation of Promises for Swift.

- [Features](#features)
- [Basic Usage](#basic-usage)
	- [`Promise`](#promise)
	- [`then`](#then)
	- [`catch`](#catch)
	- [`finally`](#finally)
	- [`Promise.resolve/reject`](#promise.resolvereject)
	- [`Promise.all`](#promise.all)
	- [`Promise.race`](#promise.race)
- [Advanced Usage](#advanced-usage)
	- [`async/await`](#asyncawait)
	- [`suspend/resume`](#suspendresume)
	- [`cancel`](#cancel)
- [Sample](#sample)
- [Installation](#installation)
- [License](#license)

## Features

### High-performance
Promises closures are called synchronously one by one if they are on the same queue and asynchronous otherwise.

### Lightweight
Whole implementation consists on several hundred lines of code.

### Memory safe
PromiseQ is based on `struct` and a stack of callbacks that removes many problems of memory management such as reference cycles etc.

### Standard API
Based on JavaScript [Promises/A+](https://promisesaplus.com/) spec, supports `async/await` and it also includes standard methods: `Promise.all`, `Promise.race`, `Promise.resolve/reject`.

### Suspension
It is an additional useful feature to `suspend` the execution of promises and `resume` them later. Suspension does not affect the execution of a promise that has already begun it stops execution of next promises.

### Cancelation
It is possible to `cancel` all queued promises at all in case to stop an asynchronous logic. Cancellation does not affect the execution of a promise that has already begun it cancels execution of the next promises.

## Basic Usage

### `Promise`

Promise is a generic type that represents an asynchronous operation and you can create it in a simple way with a closure e.g.:

``` swift
Promise {
	try String(contentsOfFile: file)
}
```

The provided closure is called asynchronously after the promise is created. By default the closure runs on the global default queue `DispatchQueue.global()` but you can also specify a needed queue to run:

``` swift
Promise(.main) {
	self.label.text = try String(contentsOfFile: file) // Runs on the main queue
}
```

The promise can be resolved when the closure returns a value or rejected when the closure throws an error.

Also the closure can settle the promise with `resolve/reject` callbacks for asynchronous tasks:

``` swift
Promise { resolve, reject in
	// Will be resolved after 2 secs
	DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
		resolve("done")
	}
}
```


### `then`

It takes a provided closure and returns new promise. The closure runs when the current promise is resolved, and receives the result.

``` swift
Promise {
	try String(contentsOfFile: "file.txt")
}
.then { text in
	print(text)
}
```

In this way we can pass results through the chain of promises:

``` swift
Promise {
	try String(contentsOfFile: "file.txt")
}
.then { text in
	return text.count
}
.then { count in
	print(count)
}
```

Also the closure can return a promise and it will be injected in the promise chain:

``` swift

Promise {
	return 200
}
.then { value in
	Promise {
		value / 10
	}
}
.then { value in
	print(value)
}
// Prints "20"

```

### `catch`

It takes a closure and return a new promise. The closure runs when the promise is rejected, and receives the error.

``` swift
Promise {
	try String(contentsOfFile: "nofile.txt") // Jumps to catch
}
.then { text in
	print(text) // Doesn't run
}
.catch { error in
	print(error.localizedDescription)
}
// Prints "The file `nofile.txt` couldn’t be opened because there is no such file."
```

### `finally`

This always runs when the promise is settled: be it resolve or reject so it is a good handler for performing cleanup etc.

``` swift
Promise {
	try String(contentsOfFile: "file.txt")
}
.finally {
	print("Finish reading") // Always runs
}
.then { text in
	print(text)
}
.catch { error in
	print(error.localizedDescription)
}
.finally {
	print("The end") // Always runs
}
```
### `Promise.resolve/reject`

These are used for compatibility e.g. when it's simple needed to return a resolved or rejected promise.

`Promise.resolve` creates a resolved promise with a given value:

``` swift
Promise {
	return 200
}

// Same as above
Promise.resolve(200)
```

`Promise.reject` creates a rejected promise with a given error:

``` swift
Promise {
	throw error
}

// Same as above
Promise.reject(error)
```

### `Promise.all`

It returns a promise that resolves when all listed promises from the provided array are resolved, and the array of their results becomes its result. If any of the promises is rejected, the promise returned by `Promise.all` immediately rejects with that error:

``` swift
Promise.all([
    Promise {
        return "Hello"
    },
    Promise { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            resolve("World")
        }
    }
])
.then { results in
    print(results)
}
// Prints ["Hello", "World"]
```

You can set `settled=true` param to make a promise that resolves when all listed promises are settled regardless of their results:

``` swift
Promise.all(settled: true, [
    Promise<Any> { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            reject(error)
        }
    },
    Promise {
        return 200
    },
])
.then { results in
    print(results)
}
// Prints [error, 200]

```

### `Promise.race`

It makes a promise that waits only for the first settled promise from the given array and gets its result (or error).

``` swift
Promise.race([
	Promise { resolve, reject in
		DispatchQueue.main.asyncAfter(deadline: .now() + 2) { // Wait 2 secs
			reject("Error")
		}
	},
	Promise { resolve, reject in
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // Wait 1 sec
			resolve(200)
		}
	}
])
.then {
	print($0)
}
// Prints "200"
```

## Advanced Usage

### `async/await`

It's a special notation to work with promises in a more comfortable way and it’s easy to understand and use.

`async` is a alias for `Promise` so you can use it to create a promise as well:

``` swift
// Returns a promise with `String` type
func readFile(_ file: String) -> async<String> {
	return async {
		try String(contentsOfFile: file)
	}
}
```

`await()` is a function that **synchronously** waits for a result of the promise or throws an error otherwise.

``` swift
let text = try readFile("file.txt").await()
```

To avoid blocking the current queue (such as main UI queue) we can pass `await()` inside the other promise (async block) and use `catch` to handle errors as usual:

``` swift
async {
	let text = try readFile("file.txt").await()
	print(text)
}
.catch { error in
	print(error.localizedDescription)
}
```

### `suspend/resume`

`suspend()` temporarily suspends a promise. Suspension does not affect the execution of the current promise that has already begun it stops execution of next promises in the chain. The promise can continue executing at a later time with `resume()`.

``` swift
let promise = Promise {
	String(contentsOfFile: file)
}
promise.suspend()
...
// Later
promise.resume()
```

### `cancel`

Cancels execution of the promise. Cancelation does not affect the execution of the promise that has already begun it cancels execution of next promises in the chain.

``` swift
let promise = Promise {
	String(contentsOfFile: file) // Never runs
}
.then { text in
	print(text) // Never runs
}
promise.cancel()
```

## Sample

There are to variants of code to fetch avatars of first 30 GitHub users that use [`fetch(path:String)`](fetch.md) utility function and [`User`](fetch.md) struct to parse a json response.

Using `then`:

``` swift
fetch("https://api.github.com/users") // Load json with users
.then { data in
	try JSONDecoder().decode([User].self, from: data) // Parse json
}
.then { users -> Promise<Array<Data>> in
	guard users.count > 0 else {
		throw "Users list is empty"
	}
	return Promise.all( // Load avatars of all users
		users
		.map { $0.avatar_url }
		.map { fetch($0) }
	)
}
.then { results in
	results.map { UIImage(data: $0) } // Create array of images
}
.then(.main) { images in
	print(images.count) // Print a count of images on the main queue
}
.catch { error in
	print("Error: \(error)")
}
```

Using `async/await`:

``` swift
async {
	let usersData = try fetch("https://api.github.com/users").await() // Load json with users

	let users = try JSONDecoder().decode([User].self, from: usersData) // Parse json
	guard users.count > 0 else {
		throw "Users list is empty"
	}

	let imagesData = try async.all( // Load avatars of all users
		users
			.map { $0.avatar_url }
			.map { fetch($0) }
	).await()

	let images = imagesData.map { UIImage(data: $0) } // Create array of images

	async(.main) {
		print(images.count) // Print a count of images on the main queue
	}
}
.catch { error in
	print("Error: \(error)")
}
```

## Installation

### Swift Package Manager (SPM)

Select `Xcode` > `File` > `Swift Packages` > `Add Package Dependency...` > Paste `https://github.com/ikhvorost/PromiseQ.git` and then `import PromiseQ` in source files.

For Swift packages:

``` swift
dependencies: [
    .package(url: "https://github.com/ikhvorost/PromiseQ.git", from: "1.0.0")
]
```

### Manual

Just copy source files to your project.

## License

PromiseQ is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
