/*
 * Copyright (c) 2023 European Commission
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import Foundation

public enum NetworkingError: LocalizedError {
  case error(String)
}

public protocol NetworkingServiceType: Sendable {
  var session: URLSession { get }
  func get(
    url: URL,
    headers: [String: String]
  ) async -> Result<String, NetworkingError>
}

public final class NetworkingService: NetworkingServiceType {
  
  public let session: URLSession
  
  public init(session: URLSession = .shared) {
    self.session = session
  }
  
  public func get(
    url: URL,
    headers: [String: String]
  ) async -> Result<String, NetworkingError> {
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    
    do {
      let (data, response) = try await session.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
      else {
        return .failure(
          .error(
            "Bad server response"
          )
        )
      }
      
      guard let string = String(data: data, encoding: .utf8) else {
        return .failure(.error("Failed to decode JWT from response"))
      }
      
      return .success(string)
      
    } catch {
      return .failure(
        .error(
          error.localizedDescription
        )
      )
    }
  }
}

