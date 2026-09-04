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

public enum NetworkingError: LocalizedError, Equatable {
  case error(String)
  case invalidURLScheme
  case privateIPAddress
  case localhostNotAllowed

  public var errorDescription: String? {
    switch self {
    case .error(let message):
      return message
    case .invalidURLScheme:
      return "URL must use HTTPS scheme"
    case .privateIPAddress:
      return "Private IP addresses are not allowed"
    case .localhostNotAllowed:
      return "Localhost is not allowed"
    }
  }
}

public protocol NetworkingServiceType: Sendable {
  var session: URLSession { get }
  func get(
    url: URL,
    headers: [String: String]
  ) async -> Result<Data, NetworkingError>
}

public actor NetworkingService: NetworkingServiceType {

  public let session: URLSession

  /// Default ephemeral session configuration.
  /// Ephemeral sessions don't persist cookies, caches, or credentials to disk,
  /// preventing cross-request tracking and improving privacy.
  private static let ephemeralSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    return URLSession(configuration: config)
  }()

  public init(session: URLSession? = nil) {
    self.session = session ?? Self.ephemeralSession
  }
  
  public func get(
    url: URL,
    headers: [String: String]
  ) async -> Result<Data, NetworkingError> {

    // Validate URL security before fetching (SSRF prevention)
    do {
      try url.validateForStatusFetch()
    } catch let error as NetworkingError {
      return .failure(error)
    } catch {
      return .failure(.error(error.localizedDescription))
    }

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
      
      return .success(data)
      
    } catch {
      return .failure(
        .error(
          error.localizedDescription
        )
      )
    }
  }
}

// MARK: - URL Security Validation

extension URL {
  /// Validates the URL for secure status list fetching.
  /// Requires HTTPS and blocks private/localhost addresses to prevent SSRF attacks.
  func validateForStatusFetch() throws {
    // Require HTTPS scheme
    guard scheme?.lowercased() == "https" else {
      throw NetworkingError.invalidURLScheme
    }

    guard let host = self.host?.lowercased() else {
      throw NetworkingError.error("Missing host in URL")
    }

    // Block localhost variants
    if host == "localhost" || host == "127.0.0.1" || host == "::1" {
      throw NetworkingError.localhostNotAllowed
    }

    // Block private IP ranges
    if isPrivateIPAddress(host) {
      throw NetworkingError.privateIPAddress
    }
  }

  /// Checks if the host is a private IP address.
  /// Blocks: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 127.0.0.0/8
  private func isPrivateIPAddress(_ host: String) -> Bool {
    // Split into octets for IPv4 check
    let parts = host.split(separator: ".").compactMap { Int($0) }

    guard parts.count == 4,
          parts.allSatisfy({ $0 >= 0 && $0 <= 255 }) else {
      // Not a valid IPv4 address, allow (could be hostname)
      return false
    }

    let first = parts[0]
    let second = parts[1]

    // 10.0.0.0/8 - Class A private
    if first == 10 {
      return true
    }

    // 172.16.0.0/12 - Class B private (172.16.x.x - 172.31.x.x)
    if first == 172 && (second >= 16 && second <= 31) {
      return true
    }

    // 192.168.0.0/16 - Class C private
    if first == 192 && second == 168 {
      return true
    }

    // 127.0.0.0/8 - Loopback
    if first == 127 {
      return true
    }

    // 169.254.0.0/16 - Link-local
    if first == 169 && second == 254 {
      return true
    }

    return false
  }
}
