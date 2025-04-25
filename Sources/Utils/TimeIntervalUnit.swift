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

public enum TimeIntervalUnit {
  case seconds
  case minutes
  case hours
  case days
  case weeks
  
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
  
  public func toTimeInterval(multiplier: Double) -> TimeInterval {
    return value * multiplier
  }
}
