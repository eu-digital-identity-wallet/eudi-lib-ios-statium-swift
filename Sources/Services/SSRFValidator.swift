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

/// Validates URLs for SSRF protection in Status List fetching.
///
/// This validator:
/// - Requires HTTPS scheme
/// - Blocks localhost and .localhost subdomains
/// - Resolves DNS and validates all resolved addresses are public
/// - Provides redirect validation via URLSession delegate
///
/// ## DNS Rebinding Caveat
///
/// This implementation validates resolved addresses before making requests, but URLSession
/// may perform its own DNS resolution when establishing the connection. This creates a
/// potential TOCTOU (time-of-check-time-of-use) race condition where:
/// 1. We resolve and validate the hostname → public IP
/// 2. URLSession resolves again → attacker has changed DNS to private IP
///
/// Mitigations in place:
/// - Short DNS TTLs are common but not universal
/// - The redirect validation catches post-connection rebinding via redirects
/// - Most practical SSRF attacks use direct private URLs rather than rebinding
///
/// For applications requiring stronger guarantees, consider:
/// - Using a custom URLProtocol that pins the resolved address
/// - Deploying network-level controls (egress filtering)
///
package final class SSRFValidator: Sendable {

  private let dnsResolver: any DNSResolverType

  package init(dnsResolver: any DNSResolverType = SystemDNSResolver()) {
    self.dnsResolver = dnsResolver
  }

  /// Validates a URL for safe Status List fetching.
  /// - Parameter url: The URL to validate.
  /// - Throws: `NetworkingError` if the URL fails validation.
  package func validate(url: URL) async throws {
    // 1. Require HTTPS scheme
    guard url.scheme?.lowercased() == "https" else {
      throw NetworkingError.invalidURLScheme
    }

    // 2. Extract and validate host
    guard let host = url.host?.lowercased() else {
      throw NetworkingError.missingHost
    }

    // 3. Block localhost variants
    try validateHostname(host)

    // 4. Check if host is already an IP address
    let validationResult = IPAddressValidator.validate(host)
    switch validationResult {
    case .allowed:
      return // Valid public IP
    case .denied(let reason):
      if reason != .invalidAddress {
        // It's a valid IP but not public
        throw NetworkingError.nonPublicAddress(reason: reason.description)
      }
      // Not an IP address, continue to DNS resolution
    }

    // 5. Resolve DNS and validate all addresses
    try await validateResolvedAddresses(hostname: host)
  }

  /// Validates a hostname for localhost patterns.
  private func validateHostname(_ host: String) throws {
    // Block "localhost" exactly
    if host == "localhost" {
      throw NetworkingError.localhostNotAllowed
    }

    // Block .localhost TLD (RFC 6761) - e.g., "foo.localhost", "bar.foo.localhost"
    if host.hasSuffix(".localhost") {
      throw NetworkingError.localhostNotAllowed
    }
  }

  /// Resolves hostname via DNS and validates all returned addresses.
  private func validateResolvedAddresses(hostname: String) async throws {
    let addresses: [String]
    do {
      addresses = try await dnsResolver.resolve(hostname: hostname)
    } catch {
      throw NetworkingError.dnsResolutionFailed(hostname: hostname)
    }

    // All resolved addresses must be public
    for address in addresses {
      let result = IPAddressValidator.validate(address)
      if case .denied(let reason) = result {
        throw NetworkingError.nonPublicAddress(reason: reason.description)
      }
    }
  }

  /// Creates a URLSession delegate that validates redirect destinations.
  /// - Returns: A delegate that enforces SSRF protection on redirects.
  package func makeRedirectValidatingDelegate() -> SSRFRedirectDelegate {
    SSRFRedirectDelegate(validator: self)
  }
}

// MARK: - Redirect Validation Delegate

/// URLSession delegate that validates redirect destinations for SSRF protection.
///
/// This delegate intercepts HTTP redirects and validates each destination URL
/// before allowing the redirect to proceed. This prevents:
/// - Redirects from HTTPS to HTTP (downgrade attacks)
/// - Redirects to localhost or private networks
/// - Redirects to non-public IP addresses
///
package final class SSRFRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

  private let validator: SSRFValidator

  package init(validator: SSRFValidator) {
    self.validator = validator
  }

  package func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    guard let redirectURL = request.url else {
      completionHandler(nil) // Block redirect with no URL
      return
    }

    // Capture validator for the task
    let validator = self.validator

    // Validate the redirect destination asynchronously
    Task {
      do {
        try await validator.validate(url: redirectURL)
        completionHandler(request) // Allow redirect
      } catch {
        completionHandler(nil) // Block unsafe redirect
      }
    }
  }
}

// MARK: - DenialReason Description

extension IPAddressValidator.DenialReason {
  var description: String {
    switch self {
    case .loopback: return "loopback address"
    case .privateNetwork: return "private network address"
    case .linkLocal: return "link-local address"
    case .multicast: return "multicast address"
    case .unspecified: return "unspecified address"
    case .documentation: return "documentation/test address"
    case .carrierGradeNAT: return "carrier-grade NAT address"
    case .reserved: return "reserved address"
    case .uniqueLocal: return "unique local address"
    case .invalidAddress: return "invalid address"
    }
  }
}
