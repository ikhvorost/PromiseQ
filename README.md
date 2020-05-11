# PromiseQ

[![Language: Swift](https://img.shields.io/badge/language-swift-f48041.svg?style=flat)](https://developer.apple.com/swift)
![Platform: iOS 8+/macOS10.11](https://img.shields.io/badge/platform-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS%20|%20Linux-blue.svg?style=flat)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![Build Status](https://travis-ci.org/ikhvorost/PromiseQ.svg?branch=master)](https://travis-ci.org/ikhvorost/PromiseQ)
[![codecov](https://codecov.io/gh/ikhvorost/PromiseQ/branch/master/graph/badge.svg)](https://codecov.io/gh/ikhvorost/PromiseQ)

Fast, powerful and lightweight implementation of Promises on Swift.

- [Features](#features)		
- [Basic Usage](#basic-usage)		
- [Sample](#sample)
- [Documentation](#documentation)
- [Installation](#installation)
- [License](#license)

## Features

### Fast
Promise's executors (closures) are called synchronously one by one if they are on the same queue and asynchronous otherwise that gives additional speed to run.

### Lightweight
Whole implementation consists of less than three hundred lines of code.

### Memory management
PromiseQ is based on `struct` and a stack of callbacks that removes problems with reference cycles etc.

### Standard API
Based on JavaScript [Promises/A+](https://promisesaplus.com/) spec and it also includes 5 standard static methods: `Promise.all/all(settled:)`, `Promise.race`, `Promise.resolve/reject`.

### Suspension
It is an additional useful feature to `suspend` the execution of promises and `resume` them later. Suspension does not affect the execution of a promise that has already begun it stops execution of next promises.

### Cancelation
It is possible to `cancel` all queued promises at all in case to stop an asynchronous logic. Cancellation does not affect the execution of a promise that has already begun it cancels execution of the next promises.

## Basic Usage

You can use promises in simple and convenient synchronous way:

``` swift
Promise {
	try String(contentsOfFile: file)
}
.then { text in
	print(text)
}
.catch { error in
	print(error)
}
```

By default all promises executors are called on global default queue - `DispatchQueue.global()` but you can also specify a needed queue to run e.g:

``` swift
Promise {
	try String(contentsOfFile: file)
}
.then(.main) { text in
	self.label?.text = text // Runs on the main queue
}
.catch { error in
	print(error)
}
```

Use `resolve/reject` callbacks to work with a promise asynchronously:

``` swift
Promise { resolve, reject in
	// Will be resolved after 2 secs
	DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
		resolve("Hello Promise!")
	}
}
.then {
	print($0)
}
```

## Sample

Fetch avatars of first GitHub users.

``` swift
/// String errors
extension String : LocalizedError {
	public var errorDescription: String? { return self }
}

/// GitHub user fields
struct User : Codable {
	let login: String
	let avatar_url: String
}

/// Utility function to fetch data by a path
func fetch(_ path: String) -> Promise<Data> {
	Promise { resolve, reject in
		guard let url = URL(string: path) else {
			reject("Bad path")
			return
		}

		let request = URLRequest(url: url)
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

// Promise chain

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
.then { results in // Array of Data
	results.map { UIImage(data: $0) }
}
.then(.main) { images in // Array of UIImage
	// Main queue
	print(images.count)
}
.catch { error in
	print("Error: \(error)")
}
```

## Documentation

TDB

## Installation

### Swift Package Manager (SPM)

Select `Xcode` > `File` > `Swift Packages` > `Add Package Dependency...` > Paste `https://github.com/ikhvorost/PromiseQ.git` and then `import PromiseQ` in source files.

For Swift packages:

``` swift
dependencies: [
    .package(url: "https://github.com/ikhvorost/PromiseQ.git", from: "1.0")
]
```

### Manual

Just copy [PromiseQ.swift](Sources/PromiseQ/PromiseQ.swift) file to your project.

## License

PromiseQ is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
