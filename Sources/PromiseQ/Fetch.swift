//
//  Fetch.swift
//  
//  Created by Iurii Khvorost <iurii.khvorost@gmail.com> on 2021/03/02.
//  Copyright © 2021 Iurii Khvorost. All rights reserved.
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

/// The HTTP request method.
public enum HTTPMethod : String {
	/// The GET method requests a representation of the specified resource. Requests using GET should only retrieve data.
	case GET

	/// The HEAD method asks for a response identical to that of a GET request, but without the response body.
	case HEAD

	/// The POST method is used to submit an entity to the specified resource, often causing a change in state or side effects on the server.
	case POST

	/// The PUT method replaces all current representations of the target resource with the request payload.
	case PUT
	
	/// The PATCH method is used to apply partial modifications to a resource.
	case PATCH

	/// The DELETE method deletes the specified resource.
	case DELETE

	/// The CONNECT method establishes a tunnel to the server identified by the target resource.
	case CONNECT

	/// The OPTIONS method is used to describe the communication options for the target resource.
	case OPTIONS

	/// The TRACE method performs a message loop-back test along the path to the target resource.
	case TRACE
}

/// String errors
extension String : LocalizedError {
	/// A localized message describing what error occurred.
	public var errorDescription: String? { return self }
}

extension URLSessionDataTask: Asyncable {
}

extension URLSessionDownloadTask: Asyncable {
}

fileprivate func isHTTP(_ path: String) -> Bool {
	let url = path.lowercased()
	return url.hasPrefix("http://") || url.hasPrefix("https://")
}

fileprivate let ErrorNotHTTP: Error = "Not HTTP"
 
fileprivate func url(_ path: String) -> Result<URL, Error> {
	guard let url = URL(string: path) else {
		return .failure("Bad URL")
	}
	guard isHTTP(path) else {
		return .failure(ErrorNotHTTP)
	}
	return .success(url)
}

fileprivate enum ResponseResult {
	case data(Data)
	case location(URL)
}

/// Provides methods for accessing information specific to HTTP protocol responses.
public class HTTPResponse {
	/// The metadata associated with the response to an HTTP protocol URL load request.
	public let response: HTTPURLResponse
	
	private let result: ResponseResult
	
	/// HTTP status code is 200-299.
	public var ok: Bool {
		(200...299).contains(response.statusCode)
	}
	
	/// Returns a localized string corresponding to a specified HTTP status code.
	public var statusCodeDescription: String {
		"HTTP \(response.statusCode) - " + HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
	}
	
	/// Returns the response data or a downloaded file data if the response location exists.
	public var data: Data? {
		switch result {
			case let .data(data):
				return data
			case let .location(url):
				return try? Data(contentsOf: url)
		}
	}
	
	/// Returns the location of the downloaded file.
	public var location: URL? {
		if case let .location(url) = result {
			return url
		}
		return nil
	}
	
	/// Reads the response data or the file data at the location and returns as text.
	public var text: String? {
		data != nil
			? String(data: data!, encoding: .utf8)
			: nil
	}
	
	/// Parse the response data or the file data at the location and returns as dictionary.
	public var json: Any? {
		data != nil
			? try? JSONSerialization.jsonObject(with: data!)
			: nil
	}
	
	fileprivate init(response: HTTPURLResponse, result: ResponseResult) {
		self.response = response
		self.result = result
	}
	
	private func clean() {
		if case let .location(url) = result {
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}
	
	deinit {
		clean()
	}
}

public extension URLSession  {
	
	/// Creates a promise that retrieves the contents of a HTTP request object.
	///
	/// By creating a promise based on a request object with the session, you can tune various aspects of the task’s
	/// behaviour, including the cache policy and timeout interval.
	/// 
	///		let url = URL(string: "https://google.com")!
	///		let request = URLRequest(url: url)
	///
	///		URLSession.shared.fetch(request)
	///		.then { response in
	///			if response.ok {
	///				print(response.statusCodeDescription)
	///			}
	///		}
	///		// Prints: HTTP 200 - no error
	///
	/// - Parameters:
	/// 	- request: A URL request object that provides the URL, cache policy, request type, body data or body stream, and so on.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	/// - Returns: A new `Promise<HTTPResponse>`
	/// - SeeAlso: `HTTPResponse`
	///
	func fetch(_ request: URLRequest, retry: Int = 0) -> Promise<HTTPResponse> {
		guard let url = request.url?.absoluteString, isHTTP(url) else {
			return Promise<HTTPResponse>.reject(ErrorNotHTTP)
		}
		
		return Promise<HTTPResponse>(retry: retry) { resolve, reject, task in
			task = self.dataTask(with: request) { data, response, error in
				guard error == nil else {
					reject(error!)
					return
				}
				
				assert(data != nil)
				resolve(HTTPResponse(response: response as! HTTPURLResponse, result: .data(data!)))
			}
			task?.resume()
		}
	}
	
	/// Creates a promise that retrieves the contents of a HTTP URL object.
	///
	/// By creating a promise based on a HTTP URL object with the URL session, you can tune various aspects of the task’s
	/// behaviour, including the cache policy and timeout interval.
	///
	///		let url = URL(string: "https://google.com")!
	///
	///		URLSession.shared.fetch(url)
	///		.then { response in
	///			if response.ok {
	///				print(response.statusCodeDescription)
	///			}
	///		}
	///		// Prints: HTTP 200 - no error
	///
	/// - Parameters:
	/// 	- url: The URL for the request.
	/// 	- method: The HTTP request method.
	/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
	/// 	- body: The data sent as the message body of a request, such as for an HTTP POST request.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	/// - Returns: A new `Promise<HTTPResponse>`
	/// - SeeAlso: `HTTPResponse`
	///
	func fetch(_ url: URL, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
		guard isHTTP(url.absoluteString) else {
			return Promise<HTTPResponse>.reject(ErrorNotHTTP)
		}
		
		var request = URLRequest(url: url)
		request.httpMethod = method.rawValue
		request.allHTTPHeaderFields = headers
		request.httpBody = body
		
		return fetch(request, retry: retry)
	}
	
	/// Creates a promise that retrieves the contents of a HTTP URL path.
	///
	/// By creating a promise based on a HTTP URL path with the URL session, you can tune various aspects of the task’s
	/// behaviour, including the cache policy and timeout interval.
	///
	///		URLSession.shared.fetch("https://google.com")
	///		.then { response in
	///			if response.ok {
	///				print(response.statusCodeDescription)
	///			}
	///		}
	///		// Prints: HTTP 200 - no error
	///
	/// - Parameters:
	/// 	- path: The HTTP URL path for the request.
	/// 	- method: The HTTP request method.
	/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
	/// 	- body: The data sent as the message body of a request, such as for an HTTP POST request.
	///		- retry: The max number of retry attempts to resolve the promise after rejection.
	/// - Returns: A new `Promise<HTTPResponse>`
	/// - SeeAlso: `HTTPResponse`
	///
	func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
		switch url(path) {
			case let .failure(error):
				return Promise<HTTPResponse>.reject(error)
			case let .success(url):
				return fetch(url, method: method, headers: headers, body: body, retry: retry)
		}
	}

}

/// Creates a promise that retrieves the contents of a HTTP URL path.
///
/// Creating a promise based on a HTTP URL path on the `URLSession.shared`.
///
///		fetch("https://google.com")
///		.then { response in
///			if response.ok {
///				print(response.statusCodeDescription)
///			}
///		}
///		// Prints: HTTP 200 - no error
///
/// - Parameters:
/// 	- path: The HTTP URL path for the request.
/// 	- method: The HTTP request method.
/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
/// 	- body: The data sent as the message body of a request, such as for an HTTP POST request.
///		- retry: The max number of retry attempts to resolve the promise after rejection.
/// - Returns: A new `Promise<HTTPResponse>`
/// - SeeAlso: `HTTPResponse`
///
public func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
	URLSession.shared.fetch(path, method: method, headers: headers, body: body, retry: retry)
}

// MARK: - Download

/// Function that periodically informs about the upload/download’s progress.
///
/// - Parameters:
/// 	- task: The upload/download task.
/// 	- bytes: The total number of bytes sent/transferred.
/// 	- totalBytes: The expected length of the data.
///
public typealias Progress = (_ task: URLSessionTask, _ bytes: Int64, _ totalBytes: Int64) -> Void

private class SessionDownloadDelegate: NSObject, URLSessionDownloadDelegate {
	let resolve: (HTTPResponse) -> Void
	let reject: (Error) -> Void
	let progress: Progress?
	
	init(resolve: @escaping (HTTPResponse) -> Void, reject: @escaping (Error) -> Void, progress: Progress?) {
		self.resolve = resolve
		self.reject = reject
		self.progress = progress
		super.init()
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		progress?(downloadTask, totalBytesWritten, totalBytesExpectedToWrite)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		session.invalidateAndCancel()
		
		if error != nil {
			reject(error!)
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		session.invalidateAndCancel()
		
		// Rename
		var url = location
		let name = "pq_" + location.lastPathComponent
		var values = URLResourceValues()
		values.name = name
		try? url.setResourceValues(values)
		url = (url as NSURL).deletingLastPathComponent!.appendingPathComponent(name)

		let response = HTTPResponse(response: downloadTask.response as! HTTPURLResponse, result: .location(url))
		resolve(response)
	}
}

/// Creates a promise that retrieves the contents of a HTTP URL path and saves the results to a file.
///
///		download("https://google.com")
///		.then { response in
/// 		if response.ok, let location = response.location {
///				print(location.absoluteURL)
///			}
///		}
///		// Prints: file:///var/folders/nt/mrsc3jhd13j8zhrhxy4x23y40000gp/T/pq_CFNetworkDownload_hGKuLu.tmp
///
/// - Parameters:
/// 	- path: The HTTP path for the request.
/// 	- method: The HTTP request method.
/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
/// 	- body: The data sent as the message body of a request, such as for an HTTP POST request.
///		- retry: The max number of retry attempts to resolve the promise after rejection.
///		- progress: Periodically informs about the download’s progress.
/// - Returns: A new `Promise<HTTPResponse>`.
/// - SeeAlso: `HTTPResponse`, `Progress`.
///
public func download(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0, progress: Progress? = nil) -> Promise<HTTPResponse> {
	switch url(path) {
		case let .failure(error):
			return Promise<HTTPResponse>.reject(error)
		
		case let .success(url):
			var request = URLRequest(url: url)
			request.httpMethod = method.rawValue
			request.allHTTPHeaderFields = headers
			request.httpBody = body
			
			return Promise<HTTPResponse>(retry: retry) { resolve, reject, task in
				let delegate = SessionDownloadDelegate(resolve: resolve, reject: reject, progress: progress)
				let session = URLSession.init(configuration: .default, delegate: delegate, delegateQueue: nil)
				
				task = session.downloadTask(with: request)
				task?.resume()
			}
	}
}

// MARK: - Upload

private class SessionTaskDelegate: NSObject, URLSessionTaskDelegate {
	let progress: Progress?

	init(progress: Progress?) {
		self.progress = progress
		super.init()
	}

	func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
		progress?(task, totalBytesSent, totalBytesExpectedToSend)
	}
}

private func upload(_ path: String, data: Data?, file: URL?, method: HTTPMethod = .POST, headers: [String : String]? = nil,
					retry: Int = 0, progress: Progress?) -> Promise<HTTPResponse> {
	switch url(path) {
		case let .failure(error):
			return Promise<HTTPResponse>.reject(error)
		
		case let .success(url):
			var request = URLRequest(url: url)
			request.httpMethod = method.rawValue
			request.allHTTPHeaderFields = headers
			
			return Promise<HTTPResponse>(retry: retry) { resolve, reject, task in
				let delegate = SessionTaskDelegate(progress: progress)
				let session = URLSession.init(configuration: .default, delegate: delegate, delegateQueue: nil)
				
				let completion = { (data: Data?, response: URLResponse?, error: Error?) in
					session.invalidateAndCancel()
					
					guard error == nil else {
						reject(error!)
						return
					}
					
					assert(data != nil)
					resolve(HTTPResponse(response: response as! HTTPURLResponse, result: .data(data!)))
				}
				
				task = file != nil
					? session.uploadTask(with: request, fromFile: file!, completionHandler: completion)
					: session.uploadTask(with: request, from: data, completionHandler: completion)
				task?.resume()
			}
	}
}

/// Creates a promise that uploads the provided data to HTTP URL path.
///
///		upload(path, data: data) { task, sent, total in
///			let percent = Double(sent) / Double(total)
///		  	print(percent)
///		}
///		.then { response in
///			if response.ok {
///				print(response.statusCodeDescription)
///		   	}
///		}
///		// Prints:
///		0.03125
///		0.0625
///		...
///		0.9375
///		1.0
///		HTTP 200 - no error
///
/// - Parameters:
/// 	- path: The HTTP path for the request.
/// 	- data: The body data for the request..
/// 	- method: The HTTP request method.
/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
/// 	- retry: The max number of retry attempts to resolve the promise after rejection.
/// 	- progress: Periodically informs about the uploads’s progress.
/// - Returns: A new `Promise<HTTPResponse>`.
/// - SeeAlso: `HTTPResponse`, `Progress`.
///
public func upload(_ path: String, data: Data, method: HTTPMethod = .POST, headers: [String : String]? = nil, retry: Int = 0, progress: Progress? = nil) -> Promise<HTTPResponse> {
	return upload(path, data: data, file: nil, method: method, headers: headers, retry: retry, progress: progress)
}

/// Creates a promise that uploads the specified file to HTTP URL path.
///
///		upload(path, file: file) { task, sent, total in
///			let percent = Double(sent) / Double(total)
///		  	print(percent)
///		}
///		.then { response in
///			if response.ok {
///				print(response.statusCodeDescription)
///		   	}
///		}
///		// Prints:
///		0.03125
///		0.0625
///		...
///		0.9375
///		1.0
///		HTTP 200 - no error
///
/// - Parameters:
/// 	- path: The HTTP path for the request.
/// 	- file: The URL of the file to upload..
/// 	- method: The HTTP request method.
/// 	- headers: A dictionary containing all of the HTTP header fields for a request.
/// 	- retry: The max number of retry attempts to resolve the promise after rejection.
/// 	- progress: Periodically informs about the uploads’s progress.
/// - Returns: A new `Promise<HTTPResponse>`.
/// - SeeAlso: `HTTPResponse`, `Progress`.
///
public func upload(_ path: String, file: URL, method: HTTPMethod = .POST, headers: [String : String]? = nil, retry: Int = 0, progress: Progress? = nil) -> Promise<HTTPResponse> {
	guard FileManager.default.fileExists(atPath: file.path) else {
		return Promise<HTTPResponse>.reject("File not found")
	}
	return upload(path, data: nil, file: file, method: method, headers: headers, retry: retry, progress: progress)
}
