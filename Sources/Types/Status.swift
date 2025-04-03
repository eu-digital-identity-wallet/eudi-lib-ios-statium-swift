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

import Foundation

/// The registered status types
public enum Status: Equatable, Sendable {
  case valid
  case invalid
  case suspended
  case applicationSpecific(UInt8)
  case reserved(UInt8)
  
  /// Converts the status to a Byte representation
  public func toByte() -> UInt8 {
    switch self {
    case .valid: return TokenStatusListSpec.statusValid
    case .invalid: return TokenStatusListSpec.statusInvalid
    case .suspended: return TokenStatusListSpec.statusSuspended
    case .applicationSpecific(let value): return value
    case .reserved(let value): return value
    }
  }
  
  /// Creates a `Status` given a `value`.
  public static func fromByte(_ value: UInt8) -> Status {
    if value == TokenStatusListSpec.statusValid { return .valid }
    if value == TokenStatusListSpec.statusInvalid { return .invalid }
    if value == TokenStatusListSpec.statusSuspended { return .suspended }
    if isApplicationSpecific(value) { return .applicationSpecific(value) }
    return .reserved(value)
  }
  
  /// Checks if the given `value` is application-specific
  private static func isApplicationSpecific(_ value: UInt8) -> Bool {
    let range = TokenStatusListSpec.statusApplicationSpecificRangeStart...TokenStatusListSpec.statusApplicationSpecificRangeEnd
    return value == TokenStatusListSpec.statusApplicationSpecific ||
    range.contains(value)
  }
}


