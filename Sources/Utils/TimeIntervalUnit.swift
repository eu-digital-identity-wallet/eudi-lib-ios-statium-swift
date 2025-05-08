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

/// A unit of time used to convert to `TimeInterval` values.
public enum TimeIntervalUnit {
  /// Represents seconds as a unit of time.
  case seconds
  /// Represents minutes as a unit of time.
  case minutes
  /// Represents hours as a unit of time.
  case hours
  /// Represents days as a unit of time.
  case days
  /// Represents weeks as a unit of time.
  case weeks
  
  /// The raw time interval value in seconds for the unit.
  ///
  /// - `seconds` = 1
  /// - `minutes` = 60
  /// - `hours` = 3600
  /// - `days` = 86400
  /// - `weeks` = 604800
  public var value: TimeInterval {
    switch self {
    case .seconds:
      return 1
    case .minutes:
      return 60
    case .hours:
      return 60 * 60
    case .days:
      return 60 * 60 * 24
    case .weeks:
      return 60 * 60 * 24 * 7
    }
  }
  
  
  /// Converts the unit to a `TimeInterval` using the given multiplier.
  ///
  /// - Parameter multiplier: A `Double` value that multiplies the base unit. Defaults to `1.0`.
  /// - Returns: The corresponding `TimeInterval` in seconds. If the multiplier is `0`, the result will be `0`.
  public func toTimeInterval(multiplier: Double = 1.0) -> TimeInterval {
    return value * multiplier
  }
}
