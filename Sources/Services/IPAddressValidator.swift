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

/// Validates IP addresses for SSRF protection.
/// Uses a deny-by-default approach: only addresses confirmed to be public Internet addresses are allowed.
package enum IPAddressValidator {

  /// Result of IP address validation.
  package enum ValidationResult: Equatable, Sendable {
    case allowed
    case denied(reason: DenialReason)
  }

  /// Reasons why an address was denied.
  package enum DenialReason: Equatable, Sendable {
    case loopback
    case privateNetwork
    case linkLocal
    case multicast
    case unspecified
    case documentation
    case carrierGradeNAT
    case reserved
    case uniqueLocal
    case invalidAddress
  }

  // MARK: - IPv4 Reserved Ranges (RFC 6890 and related)

  /// Represents an IPv4 CIDR range with its denial reason.
  private struct IPv4Range {
    let network: UInt32
    let mask: UInt32
    let reason: DenialReason

    /// Creates a range from CIDR notation components.
    /// - Parameters:
    ///   - a, b, c, d: The four octets of the network address.
    ///   - prefixLength: The CIDR prefix length (e.g., 8 for /8).
    ///   - reason: Why addresses in this range are denied.
    init(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8, _ prefixLength: UInt8, _ reason: DenialReason) {
      self.network = (UInt32(a) << 24) | (UInt32(b) << 16) | (UInt32(c) << 8) | UInt32(d)
      self.mask = prefixLength == 0 ? 0 : ~UInt32(0) << (32 - prefixLength)
      self.reason = reason
    }

    func contains(_ ip: UInt32) -> Bool {
      (ip & mask) == (network & mask)
    }
  }

  /// All IPv4 ranges that should be blocked for SSRF protection.
  /// Based on IANA IPv4 Special-Purpose Address Registry.
  private static let ipv4DeniedRanges: [IPv4Range] = [
    // RFC 1122: "This host on this network"
    IPv4Range(0, 0, 0, 0, 8, .unspecified),

    // RFC 1918: Private-Use
    IPv4Range(10, 0, 0, 0, 8, .privateNetwork),
    IPv4Range(172, 16, 0, 0, 12, .privateNetwork),
    IPv4Range(192, 168, 0, 0, 16, .privateNetwork),

    // RFC 6598: Shared Address Space (Carrier-grade NAT)
    IPv4Range(100, 64, 0, 0, 10, .carrierGradeNAT),

    // RFC 1122: Loopback
    IPv4Range(127, 0, 0, 0, 8, .loopback),

    // RFC 3927: Link-Local
    IPv4Range(169, 254, 0, 0, 16, .linkLocal),

    // RFC 6890: IETF Protocol Assignments
    IPv4Range(192, 0, 0, 0, 24, .reserved),

    // RFC 5737: Documentation (TEST-NET-1, TEST-NET-2, TEST-NET-3)
    IPv4Range(192, 0, 2, 0, 24, .documentation),
    IPv4Range(198, 51, 100, 0, 24, .documentation),
    IPv4Range(203, 0, 113, 0, 24, .documentation),

    // RFC 7526: 6to4 Relay Anycast (deprecated)
    IPv4Range(192, 88, 99, 0, 24, .reserved),

    // RFC 2544: Benchmarking
    IPv4Range(198, 18, 0, 0, 15, .reserved),

    // RFC 5771: Multicast
    IPv4Range(224, 0, 0, 0, 4, .multicast),

    // RFC 1112: Reserved for future use + Broadcast
    IPv4Range(240, 0, 0, 0, 4, .reserved),
  ]

  // MARK: - IPv6 Reserved Ranges (RFC 6890 and related)

  /// Represents an IPv6 CIDR range with its denial reason.
  private struct IPv6Range {
    let network: [UInt8]  // 16 bytes
    let prefixLength: UInt8
    let reason: DenialReason

    func contains(_ address: [UInt8]) -> Bool {
      guard address.count == 16, network.count == 16 else { return false }

      let fullBytes = Int(prefixLength / 8)
      let remainingBits = prefixLength % 8

      // Compare full bytes
      for i in 0..<fullBytes {
        if address[i] != network[i] {
          return false
        }
      }

      // Compare remaining bits if any
      if remainingBits > 0 && fullBytes < 16 {
        let mask = UInt8(0xFF) << (8 - remainingBits)
        if (address[fullBytes] & mask) != (network[fullBytes] & mask) {
          return false
        }
      }

      return true
    }
  }

  /// All IPv6 ranges that should be blocked for SSRF protection.
  /// Based on IANA IPv6 Special-Purpose Address Registry.
  private static let ipv6DeniedRanges: [IPv6Range] = [
    // RFC 4291: Unspecified address ::/128
    IPv6Range(
      network: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 128,
      reason: .unspecified
    ),

    // RFC 4291: Loopback ::1/128
    IPv6Range(
      network: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1],
      prefixLength: 128,
      reason: .loopback
    ),

    // RFC 4291: IPv4-mapped ::ffff:0:0/96 - handled specially to validate embedded IPv4
    // (not in this list - checked separately)

    // RFC 6666: Discard prefix 100::/64
    IPv6Range(
      network: [0x01, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 64,
      reason: .reserved
    ),

    // RFC 4380: Teredo 2001::/32 - tunneling, may contain private IPv4
    IPv6Range(
      network: [0x20, 0x01, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 32,
      reason: .reserved
    ),

    // RFC 5180: Benchmarking 2001:2::/48
    IPv6Range(
      network: [0x20, 0x01, 0x00, 0x02, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 48,
      reason: .reserved
    ),

    // RFC 3849: Documentation 2001:db8::/32
    IPv6Range(
      network: [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 32,
      reason: .documentation
    ),

    // RFC 3056: 6to4 2002::/16 - handled specially to validate embedded IPv4
    // (not in this list - checked separately)

    // RFC 4193: Unique Local fc00::/7
    IPv6Range(
      network: [0xFC, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 7,
      reason: .uniqueLocal
    ),

    // RFC 4291: Link-local fe80::/10
    IPv6Range(
      network: [0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 10,
      reason: .linkLocal
    ),

    // RFC 4291: Multicast ff00::/8
    IPv6Range(
      network: [0xFF, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      prefixLength: 8,
      reason: .multicast
    ),
  ]

  // MARK: - Package API

  /// Validates whether an IP address string is a public Internet address.
  /// - Parameter address: An IPv4 or IPv6 address string (no hostname).
  /// - Returns: `.allowed` if the address is public, `.denied(reason:)` otherwise.
  package static func validate(_ address: String) -> ValidationResult {
    // Try IPv4 first
    if let ipv4Result = validateIPv4(address) {
      return ipv4Result
    }

    // Try IPv6
    if let ipv6Result = validateIPv6(address) {
      return ipv6Result
    }

    // Not a valid IP address format
    return .denied(reason: .invalidAddress)
  }

  /// Validates whether a sockaddr represents a public Internet address.
  /// - Parameter sockaddr: A pointer to a sockaddr structure.
  /// - Returns: `.allowed` if the address is public, `.denied(reason:)` otherwise.
  package static func validate(sockaddr: UnsafePointer<sockaddr>) -> ValidationResult {
    switch Int32(sockaddr.pointee.sa_family) {
    case AF_INET:
      return sockaddr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
        validateIPv4Bytes(sin.pointee.sin_addr)
      }
    case AF_INET6:
      return sockaddr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sin6 in
        validateIPv6Bytes(sin6.pointee.sin6_addr)
      }
    default:
      return .denied(reason: .invalidAddress)
    }
  }

  // MARK: - IPv4 Validation

  private static func validateIPv4(_ address: String) -> ValidationResult? {
    var sin = sockaddr_in()
    let result = address.withCString { cString in
      inet_pton(AF_INET, cString, &sin.sin_addr)
    }

    guard result == 1 else {
      return nil // Not a valid IPv4 address
    }

    return validateIPv4Bytes(sin.sin_addr)
  }

  private static func validateIPv4Bytes(_ addr: in_addr) -> ValidationResult {
    let ip = UInt32(bigEndian: addr.s_addr)

    for range in ipv4DeniedRanges {
      if range.contains(ip) {
        return .denied(reason: range.reason)
      }
    }

    return .allowed
  }

  // MARK: - IPv6 Validation

  private static func validateIPv6(_ address: String) -> ValidationResult? {
    // Handle bracket notation for URLs: [::1] -> ::1
    var cleanAddress = address
    if cleanAddress.hasPrefix("[") && cleanAddress.hasSuffix("]") {
      cleanAddress = String(cleanAddress.dropFirst().dropLast())
    }

    var sin6 = sockaddr_in6()
    let result = cleanAddress.withCString { cString in
      inet_pton(AF_INET6, cString, &sin6.sin6_addr)
    }

    guard result == 1 else {
      return nil // Not a valid IPv6 address
    }

    return validateIPv6Bytes(sin6.sin6_addr)
  }

  private static func validateIPv6Bytes(_ addr: in6_addr) -> ValidationResult {
    let bytes = withUnsafeBytes(of: addr.__u6_addr.__u6_addr8) { Array($0) }

    // Check IPv4-mapped addresses (::ffff:x.x.x.x) - validate the embedded IPv4
    if isIPv4Mapped(bytes) {
      return validateEmbeddedIPv4(bytes, startIndex: 12)
    }

    // Check 6to4 addresses (2002::/16) - validate the embedded IPv4
    if is6to4(bytes) {
      return validateEmbeddedIPv4(bytes, startIndex: 2)
    }

    // Check IPv4/IPv6 translation prefix (64:ff9b::/96) - validate the embedded IPv4
    if isNAT64(bytes) {
      return validateEmbeddedIPv4(bytes, startIndex: 12)
    }

    // Check against all denied ranges
    for range in ipv6DeniedRanges {
      if range.contains(bytes) {
        return .denied(reason: range.reason)
      }
    }

    return .allowed
  }

  // MARK: - IPv6 Special Address Detection

  /// Checks if the address is IPv4-mapped (::ffff:x.x.x.x)
  private static func isIPv4Mapped(_ bytes: [UInt8]) -> Bool {
    bytes[0..<10].allSatisfy { $0 == 0 } &&
    bytes[10] == 0xFF &&
    bytes[11] == 0xFF
  }

  /// Checks if the address is 6to4 (2002::/16)
  private static func is6to4(_ bytes: [UInt8]) -> Bool {
    bytes[0] == 0x20 && bytes[1] == 0x02
  }

  /// Checks if the address is NAT64 (64:ff9b::/96)
  private static func isNAT64(_ bytes: [UInt8]) -> Bool {
    bytes[0] == 0x00 && bytes[1] == 0x64 &&
    bytes[2] == 0xFF && bytes[3] == 0x9B &&
    bytes[4..<12].allSatisfy { $0 == 0 }
  }

  /// Validates an embedded IPv4 address within an IPv6 address.
  private static func validateEmbeddedIPv4(_ bytes: [UInt8], startIndex: Int) -> ValidationResult {
    var ipv4Addr = in_addr()
    let ipv4Bytes = bytes[startIndex..<(startIndex + 4)]
    ipv4Addr.s_addr = (UInt32(ipv4Bytes[ipv4Bytes.startIndex]) << 24) |
                      (UInt32(ipv4Bytes[ipv4Bytes.startIndex + 1]) << 16) |
                      (UInt32(ipv4Bytes[ipv4Bytes.startIndex + 2]) << 8) |
                      UInt32(ipv4Bytes[ipv4Bytes.startIndex + 3])
    ipv4Addr.s_addr = ipv4Addr.s_addr.bigEndian
    return validateIPv4Bytes(ipv4Addr)
  }
}
