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

//// [Token Status List](https://www.ietf.org/archive/id/draft-ietf-oauth-status-list-10.html)
public struct TokenStatusListSpec {
  public static let version: String = "draft-10"

  public static let status: String = "status"
  public static let statusList: String = "status_list"
  public static let idx: String = "idx"
  public static let uri: String = "uri"
  public static let bits: String = "bits"
  public static let list: String = "lst"
  public static let aggregationUri: String = "aggregation_uri"
  public static let timeToLive: String = "ttl"
  public static let time: String = "time"

  public static let statusValid: Byte = 0x00
  public static let statusInvalid: Byte = 0x01
  public static let statusSuspended: Byte = 0x02
  public static let statusApplicationSpecific: Byte = 0x03
  public static let statusApplicationSpecificRangeStart: Byte = 0x0b
  public static let statusApplicationSpecificRangeEnd: Byte = 0x0f

  public static let mediaSubtypeStatusListJWT: String = "statuslist+jwt"
  public static let mediaTypeApplicationStatusListJWT: String = "application/\(Self.mediaSubtypeStatusListJWT)"
  public static let mediaSubtypeStatusListCWT: String = "statuslist+cwt"
  public static let mediaTypeApplicationStatusListCWT: String = "application/\(Self.mediaSubtypeStatusListCWT)"
}
