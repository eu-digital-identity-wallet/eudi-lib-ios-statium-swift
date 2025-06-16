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
final class CredentialStatusTests {

  @Test
  func testValidStatus() {
    let status = CredentialStatus.valid
    #expect(status.toByte() == 0x00)
  }

  @Test
  func testInvalidStatus() {
    let status = CredentialStatus.invalid
    #expect(status.toByte() == 0x01)
  }

  @Test
  func testSuspendedStatus() {
    let status = CredentialStatus.suspended
    #expect(status.toByte() == 0x02)
  }

  @Test
  func testSpecificStatus() {
    let value: UInt8 = 100
    let status = CredentialStatus.applicationSpecific(value)
    #expect(status.toByte() == value)
  }

  @Test
  func testReservedStatus() {
    let value: UInt8 = 200
    let status = CredentialStatus.reserved(value)
    #expect(status.toByte() == value)
  }

  @Test
  func testValidByte() {
    let byte: UInt8 = 0x00
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .valid)
  }

  @Test
  func testInvalidByte() {
    let byte: UInt8 = 0x01
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .invalid)
  }

  @Test
  func testSuspendedByte() {
    let byte: UInt8 = 0x02
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .suspended)
  }

  @Test
  func testSpecificByte() {
    let byte: UInt8 = 0x03
    let status = CredentialStatus.fromByte(byte)
    #expect(status ==  .applicationSpecific(byte))
  }

  @Test
  func testReservedByte() {
    let byte: UInt8 = 0x04
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .reserved(byte))
  }
}
