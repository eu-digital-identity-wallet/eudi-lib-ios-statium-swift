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
import Testing
import Foundation

@testable import StatiumSwift

// MARK: - Mock DNS Resolver

/// Mock DNS resolver for deterministic testing without network access.
final class MockDNSResolver: DNSResolverType, @unchecked Sendable {
  private var responses: [String: Result<[String], Error>] = [:]

  func setResponse(for hostname: String, addresses: [String]) {
    responses[hostname] = .success(addresses)
  }

  func setFailure(for hostname: String) {
    responses[hostname] = .failure(DNSResolutionError.resolutionFailed(hostname: hostname))
  }

  func resolve(hostname: String) async throws -> [String] {
    guard let response = responses[hostname] else {
      throw DNSResolutionError.resolutionFailed(hostname: hostname)
    }
    return try response.get()
  }
}

// MARK: - Mock URLProtocol for Redirect Testing

/// Mock URLProtocol that simulates HTTP redirects for testing.
final class MockRedirectURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var redirectMap: [URL: URL] = [:]
  nonisolated(unsafe) static var responseData: [URL: Data] = [:]

  override class func canInit(with request: URLRequest) -> Bool {
    return true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    return request
  }

  override func startLoading() {
    guard let url = request.url else {
      client?.urlProtocol(self, didFailWithError: URLError(.badURL))
      return
    }

    // Check if this URL should redirect
    if let redirectURL = MockRedirectURLProtocol.redirectMap[url] {
      let response = HTTPURLResponse(
        url: url,
        statusCode: 302,
        httpVersion: "HTTP/1.1",
        headerFields: ["Location": redirectURL.absoluteString]
      )!

      // Create redirect request
      var redirectRequest = URLRequest(url: redirectURL)
      redirectRequest.httpMethod = request.httpMethod

      client?.urlProtocol(self, wasRedirectedTo: redirectRequest, redirectResponse: response)
      return
    }

    // Return mock response data
    if let data = MockRedirectURLProtocol.responseData[url] {
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": "application/json"]
      )!

      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } else {
      client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
    }
  }

  override func stopLoading() {}

  static func reset() {
    redirectMap = [:]
    responseData = [:]
  }
}

// MARK: - IP Address Validator Tests

@Suite
struct IPAddressValidatorTests {

  // MARK: - IPv4 Public Addresses

  @Test
  func testValidate_WhenPublicIPv4_ThenAllowed() {
    let publicIPs = ["8.8.8.8", "1.1.1.1", "208.67.222.222", "93.184.216.34"]
    for ip in publicIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .allowed, "Expected \(ip) to be allowed")
    }
  }

  // MARK: - IPv4 Loopback (127.0.0.0/8)

  @Test
  func testValidate_WhenIPv4Loopback_ThenDenied() {
    let loopbackIPs = ["127.0.0.1", "127.0.0.2", "127.255.255.255"]
    for ip in loopbackIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .loopback), "Expected \(ip) to be denied as loopback")
    }
  }

  // MARK: - IPv4 Private Networks

  @Test
  func testValidate_WhenIPv4ClassAPrivate_ThenDenied() {
    // 10.0.0.0/8
    let privateIPs = ["10.0.0.1", "10.255.255.255", "10.100.50.25"]
    for ip in privateIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .privateNetwork), "Expected \(ip) to be denied as private")
    }
  }

  @Test
  func testValidate_WhenIPv4ClassBPrivate_ThenDenied() {
    // 172.16.0.0/12
    let privateIPs = ["172.16.0.1", "172.31.255.255", "172.20.10.5"]
    for ip in privateIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .privateNetwork), "Expected \(ip) to be denied as private")
    }
  }

  @Test
  func testValidate_WhenIPv4ClassBPublic_ThenAllowed() {
    // 172.15.x.x and 172.32.x.x are public
    let publicIPs = ["172.15.255.255", "172.32.0.1"]
    for ip in publicIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .allowed, "Expected \(ip) to be allowed")
    }
  }

  @Test
  func testValidate_WhenIPv4ClassCPrivate_ThenDenied() {
    // 192.168.0.0/16
    let privateIPs = ["192.168.0.1", "192.168.1.1", "192.168.255.255"]
    for ip in privateIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .privateNetwork), "Expected \(ip) to be denied as private")
    }
  }

  // MARK: - IPv4 Link-Local

  @Test
  func testValidate_WhenIPv4LinkLocal_ThenDenied() {
    // 169.254.0.0/16 - AWS metadata endpoint is 169.254.169.254
    let linkLocalIPs = ["169.254.0.1", "169.254.169.254", "169.254.255.255"]
    for ip in linkLocalIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .linkLocal), "Expected \(ip) to be denied as link-local")
    }
  }

  // MARK: - IPv4 Carrier-Grade NAT

  @Test
  func testValidate_WhenIPv4CarrierGradeNAT_ThenDenied() {
    // 100.64.0.0/10
    let cgnatIPs = ["100.64.0.1", "100.127.255.255", "100.100.100.100"]
    for ip in cgnatIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .carrierGradeNAT), "Expected \(ip) to be denied as CGNAT")
    }
  }

  @Test
  func testValidate_WhenIPv4OutsideCGNAT_ThenAllowed() {
    // 100.63.x.x and 100.128.x.x are public
    let publicIPs = ["100.63.255.255", "100.128.0.1"]
    for ip in publicIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .allowed, "Expected \(ip) to be allowed")
    }
  }

  // MARK: - IPv4 Documentation/Test Networks

  @Test
  func testValidate_WhenIPv4Documentation_ThenDenied() {
    // TEST-NET-1: 192.0.2.0/24, TEST-NET-2: 198.51.100.0/24, TEST-NET-3: 203.0.113.0/24
    let docIPs = ["192.0.2.1", "198.51.100.1", "203.0.113.1"]
    for ip in docIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .documentation), "Expected \(ip) to be denied as documentation")
    }
  }

  // MARK: - IPv4 Multicast

  @Test
  func testValidate_WhenIPv4Multicast_ThenDenied() {
    // 224.0.0.0/4
    let multicastIPs = ["224.0.0.1", "239.255.255.255", "230.0.0.1"]
    for ip in multicastIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .multicast), "Expected \(ip) to be denied as multicast")
    }
  }

  // MARK: - IPv4 Reserved

  @Test
  func testValidate_WhenIPv4Reserved_ThenDenied() {
    // 240.0.0.0/4
    let reservedIPs = ["240.0.0.1", "255.255.255.254"]
    for ip in reservedIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .reserved), "Expected \(ip) to be denied as reserved")
    }
  }

  // MARK: - IPv6 Public Addresses

  @Test
  func testValidate_WhenPublicIPv6_ThenAllowed() {
    let publicIPs = ["2607:f8b0:4004:800::200e", "2001:4860:4860::8888"]
    for ip in publicIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .allowed, "Expected \(ip) to be allowed")
    }
  }

  // MARK: - IPv6 Loopback

  @Test
  func testValidate_WhenIPv6Loopback_ThenDenied() {
    let result = IPAddressValidator.validate("::1")
    #expect(result == .denied(reason: .loopback))
  }

  @Test
  func testValidate_WhenIPv6LoopbackBracketed_ThenDenied() {
    let result = IPAddressValidator.validate("[::1]")
    #expect(result == .denied(reason: .loopback))
  }

  // MARK: - IPv6 Link-Local

  @Test
  func testValidate_WhenIPv6LinkLocal_ThenDenied() {
    // fe80::/10
    let linkLocalIPs = ["fe80::1", "fe80::abcd:1234", "febf:ffff:ffff:ffff:ffff:ffff:ffff:ffff"]
    for ip in linkLocalIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .linkLocal), "Expected \(ip) to be denied as link-local")
    }
  }

  // MARK: - IPv6 Unique Local

  @Test
  func testValidate_WhenIPv6UniqueLocal_ThenDenied() {
    // fc00::/7 (fc00::/8 and fd00::/8)
    let uniqueLocalIPs = ["fc00::1", "fd00::1", "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"]
    for ip in uniqueLocalIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .uniqueLocal), "Expected \(ip) to be denied as unique-local")
    }
  }

  // MARK: - IPv6 Multicast

  @Test
  func testValidate_WhenIPv6Multicast_ThenDenied() {
    // ff00::/8
    let multicastIPs = ["ff00::1", "ff02::1", "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff"]
    for ip in multicastIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .multicast), "Expected \(ip) to be denied as multicast")
    }
  }

  // MARK: - IPv6 Documentation

  @Test
  func testValidate_WhenIPv6Documentation_ThenDenied() {
    // 2001:db8::/32
    let docIPs = ["2001:db8::1", "2001:db8:ffff:ffff:ffff:ffff:ffff:ffff"]
    for ip in docIPs {
      let result = IPAddressValidator.validate(ip)
      #expect(result == .denied(reason: .documentation), "Expected \(ip) to be denied as documentation")
    }
  }

  // MARK: - IPv4-Mapped IPv6

  @Test
  func testValidate_WhenIPv4MappedPublic_ThenAllowed() {
    // ::ffff:8.8.8.8
    let result = IPAddressValidator.validate("::ffff:8.8.8.8")
    #expect(result == .allowed)
  }

  @Test
  func testValidate_WhenIPv4MappedPrivate_ThenDenied() {
    // ::ffff:192.168.1.1
    let result = IPAddressValidator.validate("::ffff:192.168.1.1")
    #expect(result == .denied(reason: .privateNetwork))
  }

  // MARK: - Invalid Addresses

  @Test
  func testValidate_WhenInvalidAddress_ThenDenied() {
    let invalidAddresses = ["not-an-ip", "256.256.256.256", ""]
    for addr in invalidAddresses {
      let result = IPAddressValidator.validate(addr)
      #expect(result == .denied(reason: .invalidAddress), "Expected \(addr) to be denied as invalid")
    }
  }
}

// MARK: - SSRF Validator Tests

@Suite
struct SSRFValidatorTests {

  // MARK: - Scheme Validation

  @Test
  func testValidate_WhenHTTPScheme_ThenThrowsInvalidURLScheme() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "http://example.com/status")!

    await #expect(throws: NetworkingError.invalidURLScheme) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenHTTPSScheme_ThenSucceeds() async throws {
    let mockResolver = MockDNSResolver()
    mockResolver.setResponse(for: "example.com", addresses: ["93.184.216.34"])
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://example.com/status")!
    try await validator.validate(url: url)
  }

  @Test
  func testValidate_WhenFTPScheme_ThenThrowsInvalidURLScheme() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "ftp://example.com/status")!

    await #expect(throws: NetworkingError.invalidURLScheme) {
      try await validator.validate(url: url)
    }
  }

  // MARK: - Localhost Validation

  @Test
  func testValidate_WhenLocalhostHost_ThenThrowsLocalhostNotAllowed() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://localhost/status")!

    await #expect(throws: NetworkingError.localhostNotAllowed) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenLocalhostSubdomain_ThenThrowsLocalhostNotAllowed() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://foo.localhost/status")!

    await #expect(throws: NetworkingError.localhostNotAllowed) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenNestedLocalhostSubdomain_ThenThrowsLocalhostNotAllowed() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://bar.foo.localhost/status")!

    await #expect(throws: NetworkingError.localhostNotAllowed) {
      try await validator.validate(url: url)
    }
  }

  // MARK: - Direct IP Address Validation

  @Test
  func testValidate_WhenIPv4Loopback_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://127.0.0.1/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv4Private10_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://10.0.0.1/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv4Private172_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://172.16.0.1/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv4Private192_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://192.168.1.1/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv4LinkLocal_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://169.254.169.254/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv6Loopback_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://[::1]/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv6LinkLocal_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://[fe80::1]/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenIPv6UniqueLocal_ThenThrows() async {
    let validator = SSRFValidator(dnsResolver: MockDNSResolver())
    let url = URL(string: "https://[fd00::1]/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  // MARK: - DNS Resolution Validation

  @Test
  func testValidate_WhenDNSResolvesToPrivateIP_ThenThrows() async {
    let mockResolver = MockDNSResolver()
    mockResolver.setResponse(for: "internal.example.com", addresses: ["10.0.0.1"])
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://internal.example.com/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenDNSResolvesToPublicIP_ThenSucceeds() async throws {
    let mockResolver = MockDNSResolver()
    mockResolver.setResponse(for: "example.com", addresses: ["93.184.216.34"])
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://example.com/status")!
    try await validator.validate(url: url)
  }

  @Test
  func testValidate_WhenDNSResolvesToMixedIPs_ThenThrows() async {
    let mockResolver = MockDNSResolver()
    // One public, one private - should fail because ALL must be public
    mockResolver.setResponse(for: "mixed.example.com", addresses: ["93.184.216.34", "10.0.0.1"])
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://mixed.example.com/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenDNSFails_ThenThrows() async {
    let mockResolver = MockDNSResolver()
    mockResolver.setFailure(for: "nonexistent.example.com")
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://nonexistent.example.com/status")!

    await #expect(throws: NetworkingError.dnsResolutionFailed(hostname: "nonexistent.example.com")) {
      try await validator.validate(url: url)
    }
  }

  @Test
  func testValidate_WhenDNSResolvesToIPv6UniqueLocal_ThenThrows() async {
    let mockResolver = MockDNSResolver()
    mockResolver.setResponse(for: "ipv6.example.com", addresses: ["fd00::1"])
    let validator = SSRFValidator(dnsResolver: mockResolver)

    let url = URL(string: "https://ipv6.example.com/status")!

    await #expect(throws: NetworkingError.self) {
      try await validator.validate(url: url)
    }
  }
}

// MARK: - SystemDNSResolver Integration Tests

@Suite
struct SystemDNSResolverTests {

  @Test
  func testResolve_WhenExampleDotCom_ThenReturnsPublicIPAddresses() async throws {
    let resolver = SystemDNSResolver()
    let addresses = try await resolver.resolve(hostname: "example.com")

    // example.com should resolve to at least one address
    #expect(!addresses.isEmpty, "example.com should resolve to at least one IP address")

    // All resolved addresses should be public (not private/localhost)
    for address in addresses {
      let result = IPAddressValidator.validate(address)
      #expect(result == .allowed, "example.com resolved to non-public address: \(address)")
    }
  }

  @Test
  func testResolve_WhenInvalidHostname_ThenThrowsError() async {
    let resolver = SystemDNSResolver()

    await #expect(throws: DNSResolutionError.self) {
      _ = try await resolver.resolve(hostname: "this-hostname-does-not-exist-12345.invalid")
    }
  }
}

// MARK: - NetworkingService Integration Tests

@Suite
struct NetworkingServiceSSRFTests {

  // MARK: - Direct URL Tests

  @Test
  func testGet_WhenHTTPScheme_ThenReturnsInvalidURLScheme() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "http://example.com/status")!
    let result = await service.get(url: url, headers: [:])

    #expect(result == .failure(.invalidURLScheme))
  }

  @Test
  func testGet_WhenLocalhostHost_ThenReturnsLocalhostNotAllowed() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "https://localhost/status")!
    let result = await service.get(url: url, headers: [:])

    #expect(result == .failure(.localhostNotAllowed))
  }

  @Test
  func testGet_WhenLocalhostSubdomain_ThenReturnsLocalhostNotAllowed() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "https://foo.localhost/status")!
    let result = await service.get(url: url, headers: [:])

    #expect(result == .failure(.localhostNotAllowed))
  }

  @Test
  func testGet_WhenPrivateIPv4_ThenReturnsNonPublicAddress() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let privateIPs = ["10.0.0.1", "172.16.0.1", "192.168.1.1", "169.254.169.254"]
    for ip in privateIPs {
      let url = URL(string: "https://\(ip)/status")!
      let result = await service.get(url: url, headers: [:])

      switch result {
      case .failure(.nonPublicAddress):
        break // Expected
      default:
        Issue.record("Expected nonPublicAddress for \(ip), got \(result)")
      }
    }
  }

  @Test
  func testGet_WhenLoopbackIPv4_ThenReturnsNonPublicAddress() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "https://127.0.0.1/status")!
    let result = await service.get(url: url, headers: [:])

    switch result {
    case .failure(.nonPublicAddress):
      break // Expected
    default:
      Issue.record("Expected nonPublicAddress, got \(result)")
    }
  }

  @Test
  func testGet_WhenIPv6Loopback_ThenReturnsNonPublicAddress() async {
    let mockResolver = MockDNSResolver()
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "https://[::1]/status")!
    let result = await service.get(url: url, headers: [:])

    switch result {
    case .failure(.nonPublicAddress):
      break // Expected
    default:
      Issue.record("Expected nonPublicAddress, got \(result)")
    }
  }

  @Test
  func testGet_WhenDNSResolvesToPrivate_ThenReturnsNonPublicAddress() async {
    let mockResolver = MockDNSResolver()
    mockResolver.setResponse(for: "internal.example.com", addresses: ["192.168.1.1"])
    let service = NetworkingService(dnsResolver: mockResolver)

    let url = URL(string: "https://internal.example.com/status")!
    let result = await service.get(url: url, headers: [:])

    switch result {
    case .failure(.nonPublicAddress):
      break // Expected
    default:
      Issue.record("Expected nonPublicAddress, got \(result)")
    }
  }
}
