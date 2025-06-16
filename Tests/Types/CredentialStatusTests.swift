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
  func testToByte_WhenStatusIsValid_ThenReturnsZero() {
    let status = CredentialStatus.valid
    #expect(status.toByte() == 0x00)
  }
  
  @Test
  func testToByte_WhenStatusIsInvalid_ThenReturnsOne() {
    let status = CredentialStatus.invalid
    #expect(status.toByte() == 0x01)
  }
  
  @Test
  func testToByte_WhenStatusIsSuspended_ThenReturnsTwo() {
    let status = CredentialStatus.suspended
    #expect(status.toByte() == 0x02)
  }
  
  @Test
  func testToByte_WhenStatusIsApplicationSpecific_ThenReturnsGivenValue() {
    let value: UInt8 = 100
    let status = CredentialStatus.applicationSpecific(value)
    #expect(status.toByte() == value)
  }
  
  @Test
  func testToByte_WhenStatusIsReserved_ThenReturnsGivenValue() {
    let value: UInt8 = 200
    let status = CredentialStatus.reserved(value)
    #expect(status.toByte() == value)
  }
  
  @Test
  func testFromByte_WhenByteIsZero_ThenReturnsValid() {
    let byte: UInt8 = 0x00
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .valid)
  }
  
  @Test
  func testFromByte_WhenByteIsOne_ThenReturnsInvalid() {
    let byte: UInt8 = 0x01
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .invalid)
  }
  
  @Test
  func testFromByte_WhenByteIsTwo_ThenReturnsSuspended() {
    let byte: UInt8 = 0x02
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .suspended)
  }
  
  @Test
  func testFromByte_WhenByteIsThree_ThenReturnsApplicationSpecific() {
    let byte: UInt8 = 0x03
    let status = CredentialStatus.fromByte(byte)
    #expect(status ==  .applicationSpecific(byte))
  }
  
  @Test
  func testFromByte_WhenByteIsFour_ThenReturnsReserved() {
    let byte: UInt8 = 0x04
    let status = CredentialStatus.fromByte(byte)
    #expect(status == .reserved(byte))
  }
}
