`fetch()` is utility function to load data over HTTP by a path and it returns a promise.

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
```
