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

/// Errors that can occur during DNS resolution.
package enum DNSResolutionError: Error, Equatable, Sendable {
  case resolutionFailed(hostname: String)
  case noAddressesFound(hostname: String)
}

/// Protocol for DNS resolution, allowing injection of mock resolvers in tests.
package protocol DNSResolverType: Sendable {
  /// Resolves a hostname to its IP addresses.
  /// - Parameter hostname: The hostname to resolve.
  /// - Returns: An array of resolved IP address strings.
  /// - Throws: `DNSResolutionError` if resolution fails.
  func resolve(hostname: String) async throws -> [String]
}

/// Default DNS resolver using system DNS resolution via getaddrinfo.
package struct SystemDNSResolver: DNSResolverType {

  package init() {}

  package func resolve(hostname: String) async throws -> [String] {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC  // Both IPv4 and IPv6
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?

        let status = getaddrinfo(hostname, nil, &hints, &result)

        guard status == 0, let addrList = result else {
          continuation.resume(throwing: DNSResolutionError.resolutionFailed(hostname: hostname))
          return
        }

        defer { freeaddrinfo(addrList) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = addrList

        while let addr = current {
          if let address = Self.extractAddress(from: addr.pointee) {
            addresses.append(address)
          }
          current = addr.pointee.ai_next
        }

        if addresses.isEmpty {
          continuation.resume(throwing: DNSResolutionError.noAddressesFound(hostname: hostname))
        } else {
          continuation.resume(returning: addresses)
        }
      }
    }
  }

  private static func extractAddress(from info: addrinfo) -> String? {
    guard let sockaddr = info.ai_addr else { return nil }

    switch Int32(info.ai_family) {
    case AF_INET:
      return sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        var addr = sin.pointee.sin_addr
        inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN))
        return String(cString: buffer)
      }

    case AF_INET6:
      return sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        var addr = sin6.pointee.sin6_addr
        inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
        return String(cString: buffer)
      }

    default:
      return nil
    }
  }
}
