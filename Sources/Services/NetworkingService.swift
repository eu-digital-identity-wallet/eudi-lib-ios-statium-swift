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
  case missingHost
  case nonPublicAddress(reason: String)
  case dnsResolutionFailed(hostname: String)
  case redirectBlocked

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
    case .missingHost:
      return "URL is missing a host"
    case .nonPublicAddress(let reason):
      return "Non-public address: \(reason)"
    case .dnsResolutionFailed(let hostname):
      return "DNS resolution failed for \(hostname)"
    case .redirectBlocked:
      return "Redirect to non-public address was blocked"
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
  private let ssrfValidator: SSRFValidator
  private let redirectDelegate: SSRFRedirectDelegate

  /// Default ephemeral session configuration.
  /// Ephemeral sessions don't persist cookies, caches, or credentials to disk,
  /// preventing cross-request tracking and improving privacy.
  private static func makeEphemeralConfiguration() -> URLSessionConfiguration {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieAcceptPolicy = .never
    config.httpShouldSetCookies = false
    return config
  }

  /// Creates a NetworkingService with the default configuration.
  public init() {
    let validator = SSRFValidator()
    self.ssrfValidator = validator
    self.redirectDelegate = validator.makeRedirectValidatingDelegate()

    let config = Self.makeEphemeralConfiguration()
    self.session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
  }

  /// Creates a NetworkingService with a custom DNS resolver (for testing).
  /// - Parameter dnsResolver: DNS resolver to use for hostname resolution.
  package init(dnsResolver: any DNSResolverType) {
    let validator = SSRFValidator(dnsResolver: dnsResolver)
    self.ssrfValidator = validator
    self.redirectDelegate = validator.makeRedirectValidatingDelegate()

    let config = Self.makeEphemeralConfiguration()
    self.session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
  }

  /// Creates a NetworkingService with custom session and DNS resolver (for testing).
  /// - Parameters:
  ///   - session: Custom URLSession to use.
  ///   - dnsResolver: DNS resolver to use for hostname resolution.
  package init(session: URLSession, dnsResolver: any DNSResolverType) {
    let validator = SSRFValidator(dnsResolver: dnsResolver)
    self.ssrfValidator = validator
    self.redirectDelegate = validator.makeRedirectValidatingDelegate()
    self.session = session
  }

  public func get(
    url: URL,
    headers: [String: String]
  ) async -> Result<Data, NetworkingError> {

    // Validate URL security before fetching (SSRF prevention)
    // This performs DNS resolution and validates all resolved addresses.
    do {
      try await ssrfValidator.validate(url: url)
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

    } catch let urlError as URLError where urlError.code == .cancelled {
      // Redirect was blocked by our delegate
      return .failure(.redirectBlocked)
    } catch {
      return .failure(
        .error(
          error.localizedDescription
        )
      )
    }
  }
}
