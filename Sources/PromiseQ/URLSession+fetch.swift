//
//  URLSession+fetch.swift
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
	public var errorDescription: String? { return self }
}

extension URLSessionDataTask: Asyncable {
}

extension URLSessionDownloadTask: Asyncable {
}

fileprivate extension URL {
	/// Renaming to prevent deleting by the system
	mutating func rename() -> URL {
		let name = "pq_" + lastPathComponent
		var values = URLResourceValues()
		values.name = name
		do {
			try setResourceValues(values)
			return (self as NSURL).deletingLastPathComponent!.appendingPathComponent(name)
		}
		catch {
			print(error)
		}
		return self
	}
}

public enum Auth {
	case basic(username: String, password: String)
//	case digest(username: String, password: String)
//	case hawk
//	case oauth
	case token(String)
}

public class Response {
	public let response: HTTPURLResponse
	public let data: Data?
	public let location: URL?
	
	public var ok: Bool {
		(200...299).contains(response.statusCode)
	}
	
	public var statusCodeDescription: String {
		"HTTP \(response.statusCode): " + HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
	}
	
	public var dataText: String? {
		guard let data = data, data.count > 0 else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}
	
	public var locationData: Data? {
		if let url = location {
			return try? Data(contentsOf: url)
		}
		return nil
	}
	
	fileprivate init(response: HTTPURLResponse, data: Data? = nil, location: URL? = nil) {
		self.response = response
		self.data = data
		self.location = location
	}
	
	deinit {
		if let url = location {
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}
}

public extension URLSession  {
	
	func fetch(_ request: URLRequest, retry: Int = 0) -> Promise<Response> {
		Promise<Response>(retry: retry) { resolve, reject, task in
			task = self.dataTask(with: request) { data, response, error in
				guard error == nil else {
					reject(error!)
					return
				}
				
				guard let response = response as? HTTPURLResponse else {
					reject("No response")
					return
				}
				
				resolve(Response(response: response, data: data))
			}
			task?.resume()
		}
	}
	
	func fetch(_ url: URL, method: HTTPMethod = .GET, headers: [String : String]? = nil, auth: Auth? = nil, body: Data? = nil, retry: Int = 0) -> Promise<Response> {
		var request = URLRequest(url: url)
		request.httpMethod = method.rawValue
		
		var headers = headers ?? [String : String]()
		
		if let auth = auth {
			switch auth {
				case .basic(let username, let password):
					let data = Data("\(username):\(password)".utf8).base64EncodedData()
					if let base64 = String(data: data, encoding: .utf8) {
						headers["Authorization"] = "Basic \(base64))"
					}
					
				case .token(let token):
					headers["Authorization"] = "token \(token))"
			}
		}
		
		request.allHTTPHeaderFields = headers
		request.httpBody = body
		
		return fetch(request, retry: retry)
	}
	
	func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, auth: Auth? = nil, body: Data? = nil, retry: Int = 0) -> Promise<Response> {
		guard let url = URL(string: path) else {
			return Promise<Response>.reject("Bad path")
		}
		return fetch(url, method: method, headers: headers, auth: auth, body: body, retry: retry)
	}

}

public func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, auth: Auth? = nil, body: Data? = nil, retry: Int = 0) -> Promise<Response> {
	URLSession.shared.fetch(path, method: method, headers: headers, auth: auth, body: body, retry: retry)
}

// MARK: - Download

public typealias Progress = (Double) -> Void

private class SessionDownloadDelegate: NSObject, URLSessionDownloadDelegate {
	let resolve: (Response) -> Void
	let reject: (Error) -> Void
	let progress: Progress?
	
	init(resolve: @escaping (Response) -> Void, reject: @escaping (Error) -> Void, progress: Progress?) {
		self.resolve = resolve
		self.reject = reject
		self.progress = progress
		super.init()
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		let percent = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
		progress?(percent)
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		if error != nil {
			reject(error!)
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		session.invalidateAndCancel()
		
		guard let response = downloadTask.response as? HTTPURLResponse else {
			reject("No response")
			return
		}

		var url = location
		resolve(Response(response: response, location: url.rename()))
	}
}

public func download(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0, progress: Progress?) -> Promise<Response> {
	guard let url = URL(string: path) else {
		return Promise<Response>.reject("Bad url path")
	}
	
	var request = URLRequest(url: url)
	request.httpMethod = method.rawValue
	request.allHTTPHeaderFields = headers
	request.httpBody = body
	
	return Promise<Response>(retry: retry) { resolve, reject, task in
		let delegate = SessionDownloadDelegate(resolve: resolve, reject: reject, progress: progress)
		let session = URLSession.init(configuration: .default, delegate: delegate, delegateQueue: nil)

		task = session.downloadTask(with: request)
		task?.resume()
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
		let percent = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
		progress?(percent)
	}
}

private func upload(_ path: String, data: Data?, file: URL?, method: HTTPMethod = .POST, headers: [String : String]? = nil, retry: Int = 0, progress: Progress?) -> Promise<Response> {
	guard let url = URL(string: path) else {
		return Promise<Response>.reject("Bad url path")
	}
	
	var request = URLRequest(url: url)
	request.httpMethod = method.rawValue
	request.allHTTPHeaderFields = headers
	
	return Promise<Response>(retry: retry) { resolve, reject, task in
		let delegate = SessionTaskDelegate(progress: progress)
		let session = URLSession.init(configuration: .default, delegate: delegate, delegateQueue: nil)
		
		let completion = { (data: Data?, response: URLResponse?, error: Error?) in
			session.invalidateAndCancel()
			
			guard error == nil else {
				reject(error!)
				return
			}
			
			guard let response = response as? HTTPURLResponse else {
				reject("No response")
				return
			}
			
			resolve(Response(response: response, data: data))
		}
		
		task = file != nil
			? session.uploadTask(with: request, fromFile: file!, completionHandler: completion)
			: session.uploadTask(with: request, from: data, completionHandler: completion)
		task?.resume()
	}
}

public func upload(_ path: String, data: Data, method: HTTPMethod = .POST, headers: [String : String]? = nil, retry: Int = 0, progress: Progress?) -> Promise<Response> {
	return upload(path, data: data, file: nil, method: method, headers: headers, retry: retry, progress: progress)
}

public func upload(_ path: String, file: URL, method: HTTPMethod = .POST, headers: [String : String]? = nil, retry: Int = 0, progress: Progress?) -> Promise<Response> {
	guard FileManager.default.fileExists(atPath: file.path) else {
		return Promise<Response>.reject("File not found")
	}
	return upload(path, data: nil, file: file, method: method, headers: headers, retry: retry, progress: progress)
}
