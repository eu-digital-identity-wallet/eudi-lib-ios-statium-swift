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

@Suite
struct NetworkSecurityTests {

  // MARK: - HTTPS Requirement Tests

  @Test
  func testValidateForStatusFetch_WhenHTTPScheme_ThenThrowsInvalidURLScheme() throws {
    let url = URL(string: "http://example.com/status")!
    #expect(throws: NetworkingError.invalidURLScheme) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenHTTPSScheme_ThenSucceeds() throws {
    let url = URL(string: "https://example.com/status")!
    #expect(throws: Never.self) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenFTPScheme_ThenThrowsInvalidURLScheme() throws {
    let url = URL(string: "ftp://example.com/status")!
    #expect(throws: NetworkingError.invalidURLScheme) {
      try url.validateForStatusFetch()
    }
  }

  // MARK: - Localhost Blocking Tests

  @Test
  func testValidateForStatusFetch_WhenLocalhostHost_ThenThrowsLocalhostNotAllowed() throws {
    let url = URL(string: "https://localhost/status")!
    #expect(throws: NetworkingError.localhostNotAllowed) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenIPv4Loopback_ThenThrowsLocalhostNotAllowed() throws {
    let url = URL(string: "https://127.0.0.1/status")!
    #expect(throws: NetworkingError.localhostNotAllowed) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenIPv6Loopback_ThenThrowsLocalhostNotAllowed() throws {
    let url = URL(string: "https://[::1]/status")!
    #expect(throws: NetworkingError.localhostNotAllowed) {
      try url.validateForStatusFetch()
    }
  }

  // MARK: - Private IP Blocking Tests

  @Test
  func testValidateForStatusFetch_WhenClassAPrivate_ThenThrowsPrivateIPAddress() throws {
    // 10.0.0.0/8
    let url = URL(string: "https://10.0.0.1/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenClassBPrivateLow_ThenThrowsPrivateIPAddress() throws {
    // 172.16.0.0/12 - lower bound
    let url = URL(string: "https://172.16.0.1/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenClassBPrivateHigh_ThenThrowsPrivateIPAddress() throws {
    // 172.16.0.0/12 - upper bound
    let url = URL(string: "https://172.31.255.255/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenClassBPublic_ThenSucceeds() throws {
    // 172.15.x.x is public (outside 172.16-31 range)
    let url = URL(string: "https://172.15.0.1/status")!
    #expect(throws: Never.self) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenClassCPrivate_ThenThrowsPrivateIPAddress() throws {
    // 192.168.0.0/16
    let url = URL(string: "https://192.168.1.1/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenLoopbackRange_ThenThrowsPrivateIPAddress() throws {
    // 127.0.0.0/8 - any loopback in range
    let url = URL(string: "https://127.0.0.2/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenLinkLocal_ThenThrowsPrivateIPAddress() throws {
    // 169.254.0.0/16
    let url = URL(string: "https://169.254.1.1/status")!
    #expect(throws: NetworkingError.privateIPAddress) {
      try url.validateForStatusFetch()
    }
  }

  // MARK: - Public IP Tests

  @Test
  func testValidateForStatusFetch_WhenPublicIP_ThenSucceeds() throws {
    let url = URL(string: "https://8.8.8.8/status")!
    #expect(throws: Never.self) {
      try url.validateForStatusFetch()
    }
  }

  @Test
  func testValidateForStatusFetch_WhenPublicDomain_ThenSucceeds() throws {
    let url = URL(string: "https://status.example.com/api/v1/status")!
    #expect(throws: Never.self) {
      try url.validateForStatusFetch()
    }
  }

  // MARK: - Ephemeral Session Tests

  @Test
  func testNetworkingService_WhenDefaultInit_ThenUsesEphemeralSession() async {
    let service = NetworkingService()
    let session = await service.session

    // Ephemeral sessions have their own configuration (not .default or .shared)
    // We can verify by checking cookie policy
    #expect(session.configuration.httpCookieAcceptPolicy == .never)
    #expect(session.configuration.httpShouldSetCookies == false)
  }

  @Test
  func testNetworkingService_WhenCustomSessionProvided_ThenUsesCustomSession() async {
    let customSession = URLSession(configuration: .default)
    let service = NetworkingService(session: customSession)
    let session = await service.session

    #expect(session === customSession)
  }
}
