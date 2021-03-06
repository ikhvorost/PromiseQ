//
//  URLSession+PromiseQ.swift
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

public struct HTTPResponse {
	public let response: HTTPURLResponse
	public let data: Data?
	
	public var ok: Bool {
		(200...299).contains(response.statusCode)
	}
	
	public var text: String? {
		guard let data = data, data.count > 0 else {
			return nil
		}
		return String(data: data, encoding: .utf8)
	}
}

public extension URLSession  {
	
	func fetch(_ request: URLRequest, retry: Int = 0) -> Promise<HTTPResponse> {
		Promise<HTTPResponse>(retry: retry) { resolve, reject, task in
			task = self.dataTask(with: request) { data, response, error in
				guard error == nil else {
					reject(error!)
					return
				}
				
				let httpResponse = HTTPResponse(response: response as! HTTPURLResponse, data: data)
				resolve(httpResponse)
			}
			task?.resume()
		}
	}
	
	func fetch(_ url: URL, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
		var request = URLRequest(url: url)
		request.httpMethod = method.rawValue
		request.allHTTPHeaderFields = headers
		request.httpBody = body
		
		return fetch(request, retry: retry)
	}
	
	func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
		guard let url = URL(string: path) else {
			return Promise<HTTPResponse>.reject("Bad url path")
		}
		return fetch(url, method: method, headers: headers, body: body, retry: retry)
	}
}


// Global

public func fetch(_ path: String, method: HTTPMethod = .GET, headers: [String : String]? = nil, body: Data? = nil, retry: Int = 0) -> Promise<HTTPResponse> {
	URLSession.shared.fetch(path, method: method, headers: headers, body: body, retry: retry)
}
