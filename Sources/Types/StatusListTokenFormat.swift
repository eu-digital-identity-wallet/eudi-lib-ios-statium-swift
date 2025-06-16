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

/// An enumeration that defines the possible formats for a status list token.
///
/// This enum is used to specify whether the status list token is in JSON Web Token (JWT) format or
/// CWT format. It is used to distinguish between these two token formats in scenarios
/// where the token format affects processing or validation.
public enum StatusListTokenFormat: Sendable {

  /// Represents the JSON Web Token (JWT) format.
  case jwt

  /// Represents the CWT format.
  case cwt
}

public extension StatusListTokenFormat {
  var fieldHeaderValue: String {
    switch self {
    case .jwt:
      return TokenStatusListSpec.mediaTypeApplicationStatusListJWT
    case .cwt:
      return TokenStatusListSpec.mediaTypeApplicationStatusListCWT
    }
  }
}
