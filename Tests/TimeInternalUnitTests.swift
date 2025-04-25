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
import Testing

@testable import StatiumSwift

@Suite
final class TimeInternalUnitTests {
  
  @Test
  func testValueForAllCases() {
    #expect(TimeIntervalUnit.seconds.value == 1)
    #expect(TimeIntervalUnit.minutes.value == 60)
    #expect(TimeIntervalUnit.hours.value == 3600)
    #expect(TimeIntervalUnit.days.value == 86400)
    #expect(TimeIntervalUnit.weeks.value == 604800)
  }
  
  @Test
  func testToTimeIntervalWithMultiplier() {
    #expect(TimeIntervalUnit.seconds.toTimeInterval(multiplier: 5) == 5)
    #expect(TimeIntervalUnit.minutes.toTimeInterval(multiplier: 2) == 120)
    #expect(TimeIntervalUnit.hours.toTimeInterval(multiplier: 0.5) == 1800)
    #expect(TimeIntervalUnit.days.toTimeInterval(multiplier: 1.5) == 129600)
    #expect(TimeIntervalUnit.weeks.toTimeInterval(multiplier: 0) == 0)
  }
}

