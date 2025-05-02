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

public protocol StatusListTokenFetcherType {
  
  /// Initializes an object that conforms to `StatusListTokenFetcherType` with the provided `verifier` and `date`.
  ///
  /// - Parameter verifier: An object responsible for verifying the status list token's signature.
  /// - Parameter networkingService: An object responsible fornetworking.
  /// - Parameter date: The date used for token validation (e.g., to check expiration or issue time).
  ///
  /// This initializer is required to ensure the object is properly set up with the necessary dependencies
  /// for status retrieval and validation.
  init(
    networkingService: NetworkingServiceType,
    verifier: any VerifyStatusListTokenSignature,
    date: Date
  )
  
  /// Retrieves the status list token claims from the given URL.
  ///
  /// - Parameters:
  ///   - session: The `URLSession` instance used for network requests.
  ///   - format: The format of the status list token, either `.jwt` or `.cwt`.
  ///   - url: An optional `URL` pointing to the status list resource.
  /// - Returns: A `Result` containing either the `StatusListTokenClaims` on success or a `StatusError` on failure.
  func getStatusClaims(
    session: URLSession,
    format: StatusListTokenFormat,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError>
}

public actor StatusListTokenFetcher: StatusListTokenFetcherType {
  
  public let networkingService: any NetworkingServiceType
  public let verifier: any VerifyStatusListTokenSignature
  public let date: Date
  
  public init(
    networkingService: NetworkingServiceType = NetworkingService(),
    verifier: any VerifyStatusListTokenSignature,
    date: Date = Date()
  ) {
    self.networkingService = networkingService
    self.verifier = verifier
    self.date = date
  }
  
  public func getStatusClaims(
    session: URLSession = .shared,
    format: StatusListTokenFormat = .jwt,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    await getClaims(session: session, format: format, url: url, clockSkew: clockSkew)
  }
}

private extension StatusListTokenFetcher {
  private func getClaims(
    session: URLSession,
    format: StatusListTokenFormat,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    
    guard format == .jwt else { return .failure(.cwtNotSupported) }
    
    let jwtResult = await fetchJWT(
      from: url, format: format
    )
    
    return switch jwtResult {
    case .failure(let error):
      .failure(error)
    case .success(let jwt):
      processJWT(
        jwt,
        verifier: verifier,
        sourceURL: url.absoluteString,
        format: format,
        clockSkew: clockSkew
      )
    }
  }
  
  private func fetchJWT(
    from url: URL,
    format: StatusListTokenFormat
  ) async -> Result<String, StatusError> {
    
    let result = await networkingService.get(
      url: url,
      headers: [
        "Accept": format.fieldHeaderValue
      ]
    )
    
    switch result {
    case .success(let string):
      return .success(string)
    case .failure(let error):
      return .failure(StatusError.error(error.localizedDescription))
    }
  }
  
  private func processJWT(
    _ jwt: String,
    verifier: VerifyStatusListTokenSignature,
    sourceURL: String,
    format: StatusListTokenFormat,
    clockSkew: TimeInterval
  ) -> Result<StatusListTokenClaims, StatusError> {
    do {
      let claims = try getAndEnsureClaims(jwt, sourceURL, date, clockSkew)
      try verifier.verify(statusListToken: jwt, format: format, at: date)
      
      return .success(claims)
    } catch {
      return .failure(.error(error.localizedDescription))
    }
  }
  
  func getAndEnsureClaims(
    _ jwt: String,
    _ uri: String,
    _ date: Date,
    _ clockSkew: TimeInterval
  ) throws -> StatusListTokenClaims {
    let jwt = try JWT(
      compactJWT: jwt
    )
    
    let claims = try JSONDecoder().decode(
      StatusListTokenClaims.self,
      from: jwt.payload
    )
    
    let header = jwt.header["typ"] as? String
    if header != TokenStatusListSpec.mediaSubtypeStatusListJWT {
      throw StatusError.badJwtHeader
    }
    
    return try claims.ensureValid(uri: uri, date: date, clockSkew: clockSkew)
  }
}

extension StatusListTokenClaims {
  func ensureValid(
    uri: String,
    date: Date,
    clockSkew: TimeInterval
  ) throws -> StatusListTokenClaims {
    if uri != self.subject {
      throw StatusError.badSubject(self.subject)
    }

    if let exp = expirationTime {
      let expirationDate = Date(timeIntervalSince1970: exp)
//      guard date <= expirationDate.addingTimeInterval(clockSkew) else {
//        throw StatusError.expiredToken
//      }
    }
    
    let iat = issuedAt
    let iatDate = Date(timeIntervalSince1970: iat)
//    guard iatDate.addingTimeInterval(-clockSkew) <= date else {
//      throw StatusError.invalidIssueDate
//    }
    
    return self
  }
}
