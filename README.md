# PromiseQ

[![Language: Swift](https://img.shields.io/badge/language-swift-f48041.svg?style=flat)](https://developer.apple.com/swift)
![Platform: iOS 8+/macOS10.11](https://img.shields.io/badge/platform-iOS%20|%20macOS%20|%20tvOS%20|%20watchOS%20-blue.svg?style=flat)
[![SPM compatible](https://img.shields.io/badge/SPM-compatible-4BC51D.svg?style=flat)](https://swift.org/package-manager/)
[![build & test](https://github.com/ikhvorost/PromiseQ/actions/workflows/swift.yml/badge.svg?branch=master)](https://github.com/ikhvorost/PromiseQ/actions/workflows/swift.yml)
[![codecov](https://codecov.io/gh/ikhvorost/PromiseQ/branch/master/graph/badge.svg)](https://codecov.io/gh/ikhvorost/PromiseQ)
[![swift doc coverage](https://img.shields.io/badge/swift%20doc-100%25-f39f37)](https://github.com/SwiftDocOrg/swift-doc)

<p align="center"><img src="promiseq.png" width="380" alt="PromiseQ: Promises with async/await, suspend/resume and cancel features for Swift."></p>

Fast, powerful and lightweight implementation of Promises for Swift.

- [Features](#features)
- [Basic Usage](#basic-usage)
	- [`Promise`](#promise)
	- [`then`](#then)
	- [`catch`](#catch)
	- [`finally`](#finally)
	- [`Promise.resolve/reject`](#promiseresolvereject)
	- [`Promise.all`](#promiseall)
	- [`Promise.race`](#promiserace)
	- [`Promise.any`](#promiseany)
- [Advanced Usage](#advanced-usage)
	- [`timeout`](#timeout)
	- [`retry`](#retry)
	- [`async/await`](#asyncawait)
	- [`suspend/resume`](#suspendresume)
	- [`cancel`](#cancel)
	- [`Asyncable`](#asyncable)
- [Network requests](#network-requests)
	- [`fetch`](#fetch)
	- [`download`](#download)
	- [`upload`](#upload)
- [Samples](#samples)
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
Based on JavaScript [Promises/A+](https://promisesaplus.com/) spec, supports `async/await` and it also includes standard methods: `Promise.all`, `Promise.race`, `Promise.any`, `Promise.resolve/reject`.

### Suspension
It is an additional useful feature to `suspend` the execution of promises and `resume` them later. Suspension does not affect the execution of a promise that has already begun it stops execution of next promises.

### Cancelation
It is possible to `cancel` all queued promises at all in case to stop an asynchronous logic. Cancellation does not affect the execution of a promise that has already begun it cancels execution of the next promises.

## Basic Usage

### `Promise`

Promise is a generic type that represents an asynchronous operation and you can create it in a simple way with a closure e.g.:

```swift
Promise {
    try String(contentsOfFile: file)
}
```

The provided closure is called asynchronously after the promise is created. By default the closure runs on the global default queue `DispatchQueue.global()` but you can also specify a needed queue to run:

```swift
Promise(.main) {
    self.label.text = try String(contentsOfFile: file) // Runs on the main queue
}
```

The promise can be resolved when the closure returns a value or rejected when the closure throws an error.

Also the closure can settle the promise with `resolve/reject` callbacks for asynchronous tasks:

```swift
Promise { resolve, reject in
    // Will be resolved after 2 secs
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        resolve("done")
    }
}
```


### `then`

It takes a provided closure and returns new promise. The closure runs when the current promise is resolved, and receives the result.

```swift
Promise {
    try String(contentsOfFile: "file.txt")
}
.then { text in
    print(text)
}
```

In this way we can pass results through the chain of promises:

```swift
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

```swift
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

```swift
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

```swift
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

```swift
Promise {
    return 200
}

// Same as above
Promise.resolve(200)
```

`Promise.reject` creates a rejected promise with a given error:

```swift
Promise {
    throw error
}

// Same as above
Promise<Void>.reject(error)
```

### `Promise.all`

It returns a promise that resolves when all listed promises from the provided list are resolved, and the array of their results becomes its result. If any of the promises is rejected, the promise returned by `Promise.all` immediately rejects with that error:

```swift
Promise.all(
    Promise {
        return "Hello"
    },
    Promise { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            resolve("World")
        }
    }
)
.then { results in
    print(results)
}
// Prints ["Hello", "World"]
```

You can set `settled=true` param to make a promise that resolves when all listed promises are settled regardless of their results:

```swift
Promise.all(settled: true,
    Promise<Any> { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            reject(error)
        }
    },
    Promise {
        return 200
    }
)
.then { results in
    print(results)
}
// Prints [error, 200]
```

If there are no promises or array of promises is empty the promise resolves with empty array.

### `Promise.race`

It makes a promise that waits only for the first settled promise from the given list and gets its result or error.

```swift
Promise.race(
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
)
.then {
    print($0)
}
// Prints "200"
```

If there are no promises or array of promises is empty the promise rejects with `PromiseError.empty` error.

### `Promise.any`

It's similar to `Promise.race`, but waits only for the first fulfilled promise and gets its result.

```swift
Promise.any(
    Promise { resolve, reject in
        reject("Error")
    },
    Promise { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // Waits 1 sec
            resolve(200)
        }
    }
)
.then {
    print($0)
}
// Prints "200"
```

If there are no promises or array of promises is empty the promise rejects with `PromiseError.empty` error.

If all of the given promises are rejected, then the returned promise is rejected with `PromiseError.aggregate` – a special error that stores all promise errors.

```swift
Promise.any(
    Promise { resolve, reject in
        reject("Error")
    },
    Promise { resolve, reject in
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { // Waits 1 sec
            reject("Fail")
        }
    }
)
.catch { error in
    if case let PromiseError.aggregate(errors) = error {
        print(errors, "-", error.localizedDescription)
    }
}
// Prints: '["Error", "Fail"]' - All Promises rejected.
```

## Advanced Usage

### `timeout`

`timeout` parameter allows to wait for a promise for a time interval and reject it with `PromiseError.timedOut` error, if it doesn't resolve within the given time.

```swift
Promise(timeout: 10) { // Wait 10 secs for data
    try loadData()
}
.then(timeout: 1) { data in //  Wait 1 sec for parsed data
    try parse(data)
}
.catch(timeout: 1) { error in // Wait 1 sec to handle errors
    if case PromiseError.timedOut = error {
        print(error.localizedDescription)
    }
    else {
        handleError(error)
    }
}
```

### `retry`

`retry` parameter provides the ability to reattempt a task if the promise is rejected. By default, there is a single attempt to resolve the promise but you can increase the number of attempts with this parameter:

```swift
Promise(retry: 3) { // Makes 3 attempts to load data after the rejection
    try loadData()
}
.then { data in
    parse(data)
    ...
}
.catch { error in
    print(error.localizedDescription) // Calls if the `loadData` fails 4 times (1 + 3 retries)
}
```

### `async/await`

It's a special notation to work with promises in a more comfortable way and it’s easy to understand and use.

`async` is a alias for `Promise` so you can use it to create a promise as well:

```swift
// Returns a promise with `String` type
func readFile(_ file: String) -> async<String> {
    return async {
        try String(contentsOfFile: file)
    }
}
```

`await()` is a function that **synchronously** waits for a result of the promise or throws an error otherwise.

```swift
let text = try readFile("file.txt").await()
```

To avoid blocking the current queue (such as main UI queue) we can pass `await()` inside the other promise (async block) and use `catch` to handle errors as usual:

```swift
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

```swift
let promise = Promise {
    String(contentsOfFile: file)
}
promise.suspend()
...
// Later
promise.resume()
```

### `cancel`

Cancels execution of the promise and reject it with `PromiseError.cancelled` error. Cancelation does not affect the execution of the promise that has already begun it rejects the promise and stops execution of next promises in the chain.

```swift
let promise = Promise {
    return "Text" // Never runs
}
.then { text in
    print(text) // Never runs
}
.catch { error in
    if case PromiseError.cancelled = error {
        print(error.localizedDescription)
    }
}

promise.cancel()

// Prints: The Promise cancelled.
```

You can also break the promise chain for some conditions to call `cancel` inside a closure of any promise e.g.:

```swift
let promise = Promise {
    return getStatusCode()
}

promise.then { statusCode in
    guard statusCode == 200 else {
        promise.cancel() // Breaks the promise chain
        return
    }
    ...
}
.then {
    ... // Never runs in case of cancel
}
```


### `Asyncable`

`Asyncable` protocol represents an asynchronous task type that can be suspended, resumed and canceled:

```swift
public protocol Asyncable {
    func suspend() // Temporarily suspends a task.
    func resume() // Resumes the task, if it is suspended.
    func cancel() // Cancels the task.
}
```

Promise can manage an asynchronous task when it wraps one. For instance it's useful for network requests:

```swift
// The wrapped asynchronous task must be conformed to `Asyncable` protocol.
extension URLSessionDataTask: Asyncable {
}

let promise = Promise<Data> { resolve, reject, task in // `task` is in-out parameter
    task = URLSession.shared.dataTask(with: request) { data, response, error in
        guard error == nil else {
            reject(error!)
            return
        }
        resolve(data)
    }
    task.resume()
}

// The promise and the data task will be suspended after 2 secs and won't produce any network activity.
// but they can be resumed later.
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    promise.suspend()
}
```

You can also make your custom asynchronous task that can be managed by a promise:

```swift
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

// Promise
let promise = Promise<String> { resolve, reject, task in // `task` is in-out parameter
    task = TimeOutTask(timeOut: 3) {
        resolve("timed out") // Won't be called
    }
    task.resume()
}
.then { text in
    print(text) // Won't be called
}

// Both the promise and the timed out task will be canceled after 1 sec
DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
    promise.cancel()
}
```

## Network requests

### `fetch`

You can send network requests to the server and load new information whenever it’s needed with asynchronous `fetch` utility function. It starts the request right away and returns a promise that the calling code should use to get the result. The promise, returned by `fetch`, resolves with `HTTPResponse` object as soon as the server responds and you can use it to access to the response properties:

- `ok: Bool` - `true` if the HTTP status code is 200-299.
- `statusCodeDescription: String` – HTTP status code with description.
- `response: HTTPURLResponse` - Response metadata object, such as HTTP headers and status code.
- `data: Data?` - The data returned by the server.
- `text: String?` - text from `data`.
- `json: Any?` - json from `data`.

For example:

```swift
fetch("https://api.github.com/users/technoweenie") // Get github user's info
.then { response in
    guard response.ok else { // Check for the HTTP status code
        throw response.statusCodeDescription
    }

    guard let json = response.json as? [String: Any] else { // Get json from the returned data
        throw "No JSON"
    }

    if let name = json["name"] as? String { // Get name of the user
        print(name)
    }
}
.catch {error in
    print(error.localizedDescription)
}

// Prints: risk danger olson
```

By default `fetch` does `GET` request with default headers and empty body data but you can change that with optional parameters:

- `method: HTTPMethod` - HTTP-method, e.g. `.GET`, `.POST` etc.
- `headers: [String : String]?` - a dictionary containing all of the HTTP header fields for a request.
- `body: Data?` - the request body.
- `retry: Int` -  The max number of retry attempts to resolve the promise after rejection.

```swift
async {
    let response = try fetch(url,
        method: .POST,
        headers: ["Accept-Encoding" : "br, gzip, deflate"],
        body: data
    ).await()

    ...
}
.catch {error in
    print(error.localizedDescription)
}
```

`fetch` uses `URLSession.default` to make requests by default but you also can call it on your session instance and tune various aspects of the session’s behavior, including the cache policy, timeout interval etc.:

```swift
let config = URLSessionConfiguration.default
config.timeoutIntervalForRequest = 120
config.httpAdditionalHeaders = ["Accept-Encoding" : "br, gzip, deflate"]
let session = URLSession(configuration: config)

async {
    let response = try session.fetch(url).await()
    ...
}
.catch {error in
    print(error.localizedDescription)
}
```

### `download`

`download` works similar to `fetch` but saves data to a file and informs about the downloading progress, for instance:

```swift
async {
    let response = try download("http://speedtest.tele2.net/1MB.zip") { task, written, total in
        let percent = Double(written) / Double(total)
        print(percent)
    }.await()

    guard response.ok else {
        throw response.statusCodeDescription
    }

    guard let location = response.location else {
        throw "No location"
    }

    print(location)
}
.catch { error in
    print(error.localizedDescription)
}

// Prints
0.038433074951171875
0.10195541381835938
...
0.9263648986816406
1.0
file:///var/folders/nt/mrsc3jhd13j8zhrhxy4x23y40000gp/T/pq_CFNetworkDownload_t94Pig.tmp
```

### `upload`

`download` works similar to `fetch` but can upload data or a file to a server and informs about the uploading progress, for instance:

```swift
async {
    let response = try upload(url, data: data) { task, sent, total in
        let percent = Double(sent) / Double(total)
        print(percent)
    }.await()

    guard response.ok else {
        throw response.statusCodeDescription
    }

    print("Uploaded")
}
.catch { error in
    print(error.localizedDescription)
}

// Prints
0.03125
0.0625
...
0.96875
1.0
Uploaded
```

## Samples

There are two variants of code to `fetch` avatars of first 30 GitHub users.

Using `then`:

```swift
struct User : Codable {
    let login: String
    let avatar_url: String
}

fetch("https://api.github.com/users") // Load json with users
.then { response -> [User] in
    guard response.ok else {
        throw response.statusCodeDescription
    }

    guard let data = response.data else {
        throw "No data"
    }

    return try JSONDecoder().decode([User].self, from: data) // Parse json
}
.then { users -> Promise<Array<HTTPResponse>> in
    return Promise.all(
        users
        .map { $0.avatar_url }
        .map { fetch($0) }
    )
}
.then { responses in
    responses
        .compactMap { $0.data }
        .compactMap { UIImage(data: $0)} // Create array of images
}
.then(.main) { images in
    print(images.count) // Print a count of images on the main queue
}
.catch { error in
    print(error.localizedDescription)
}
```

Using `async/await`:

```swift
async {
    let response = try fetch("https://api.github.com/users").await()
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
            .map { $0.avatar_url }
            .map { fetch($0) }
        ).await()
        .compactMap { $0.data }
        .compactMap { UIImage(data: $0) }

	async(.main) {
		print(images.count)
	}
}
.catch { error in
    print(error.localizedDescription)
}
```

For more samples see [PromiseQTests.swift](Tests/PromiseQTests/PromiseQTests.swift).

## Installation

### XCode project

1. Select `Xcode > File > Swift Packages > Add Package Dependency...`
2. Add package repository: `https://github.com/ikhvorost/PromiseQ.git`
3. Import the package in your source files: `import PromiseQ`

### Swift Package

Add `PromiseQ` package dependency to your `Package.swift` file:

```swift
let package = Package(
    ...
    dependencies: [
        .package(url: "https://github.com/ikhvorost/PromiseQ.git", from: "1.0.0")
    ],
    targets: [
        .target(name: "YourPackage",
            dependencies: [
                .product(name: "PromiseQ", package: "PromiseQ")
            ]
        ),
        ...
    ...
)
```

## License

PromiseQ is available under the MIT license. See the [LICENSE](LICENSE) file for more info.
