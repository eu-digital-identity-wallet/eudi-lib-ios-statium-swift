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

/**
 * A reference to a status, as it would appear in a referenced token (credential)
 * nested inside a status claim, under the attribute 'status_list'
 *
 * @param index It MUST specify an Integer that represents the index to check
 * for status information in the Status List for the current Referenced Token.
 * @param uri It MUST specify a String value that identifies the Status List Token
 * containing the status information for the Referenced Token
 */

public struct StatusReference: Codable, Sendable {
  public let idx: Int
  public let uri: URL

  public init(idx: Int, uri: URL) {
    self.idx = idx
    self.uri = uri
  }

  public init?(idx: Int, uriString: String) {
    guard let url = URL(string: uriString) else { return nil }
    self.idx = idx
    self.uri = url
  }

  private enum CodingKeys: String, CodingKey {
    case idx
    case uri
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.idx = try container.decode(Int.self, forKey: .idx)

    let uriString = try container.decode(String.self, forKey: .uri)
    guard let uri = URL(string: uriString) else {
      throw DecodingError.dataCorruptedError(
        forKey: .uri,
        in: container,
        debugDescription: "Invalid URL format"
      )
    }

    self.uri = uri
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(idx, forKey: .idx)
    try container.encode(uri.absoluteString, forKey: .uri)
  }
}
