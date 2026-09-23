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
import SwiftCBOR

public protocol StatusListTokenFetcherType {

  /// Initializes an object that conforms to `StatusListTokenFetcherType` with the provided `verifier` and `dateProvider`.
  ///
  /// - Parameter verifier: An object responsible for verifying the status list token's signature.
  /// - Parameter networkingService: An object responsible for networking.
  /// - Parameter dateProvider: A closure that returns the current date for token validation.
  ///   Using a closure instead of a fixed Date ensures fresh timestamps for each operation,
  ///   preventing stale clock issues in long-lived fetcher instances.
  ///
  /// This initializer is required to ensure the object is properly set up with the necessary dependencies
  /// for status retrieval and validation.
  init(
    networkingService: NetworkingServiceType,
    verifier: any VerifyStatusListTokenSignature,
    dateProvider: @escaping @Sendable () -> Date
  )
  
  /// Retrieves the status list token claims from the given URL.
  ///
  /// - Parameters:
  ///   - format: The format of the status list token, either `.jwt` or `.cwt`.
  ///   - url: An optional `URL` pointing to the status list resource.
  ///   - clockSkew: The time tolerance applied when validating the token.
  /// - Returns: A `Result` containing either the `StatusListTokenClaims` on success or a `StatusError` on failure.
  func getStatusClaims(
    format: StatusListTokenFormat,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError>
}

public actor StatusListTokenFetcher: StatusListTokenFetcherType {

  public let networkingService: any NetworkingServiceType
  public let verifier: any VerifyStatusListTokenSignature
  /// Closure that provides the current date for each validation operation.
  /// This ensures fresh timestamps and prevents stale clock issues in long-lived instances.
  public let dateProvider: @Sendable () -> Date

  public init(
    networkingService: NetworkingServiceType = NetworkingService(),
    verifier: any VerifyStatusListTokenSignature,
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.networkingService = networkingService
    self.verifier = verifier
    self.dateProvider = dateProvider
  }
  
  public func getStatusClaims(
    format: StatusListTokenFormat = .jwt,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    await getClaims(format: format, url: url, clockSkew: clockSkew)
  }
}

private extension StatusListTokenFetcher {
  private func getClaims(
    format: StatusListTokenFormat,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    
    let fetchResult = await fetch(
      from: url,
      format: format
    )
    
    switch format {
    case .jwt:
      return switch fetchResult {
      case .success(let jwtData):
        await processJWT(
          jwtData,
          verifier: verifier,
          sourceURL: url.absoluteString,
          format: format,
          clockSkew: clockSkew
        )
      case .failure(let error):
        .failure(error)
      }
    case .cwt:
      return switch fetchResult {
      case .success(let cwtData):
        await processCWT(
          cwtData,
          verifier: verifier,
          sourceURL: url.absoluteString,
          format: format,
          clockSkew: clockSkew
        )
      case .failure(let error):
        .failure(error)
      }
    }
  }
  
  private func fetch(
    from url: URL,
    format: StatusListTokenFormat
  ) async -> Result<Data, StatusError> {
    
    let result = await networkingService.get(
      url: url,
      headers: [
        "Accept": format.fieldHeaderValue
      ]
    )
    
    switch result {
    case .success(let data):
      return .success(data)
    case .failure(let error):
      return .failure(StatusError.error(error.localizedDescription))
    }
  }
  
  private func processCWT(
    _ cwtData: Data,
    verifier: VerifyStatusListTokenSignature,
    sourceURL: String,
    format: StatusListTokenFormat,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    do {
      
      // Use fresh date for each verification to prevent stale clock issues
      let currentDate = dateProvider()
      try await verifier.verify(
        statusListToken: cwtData,
        format: format,
        at: currentDate
      )
      
      let claims = try CWTDecoder().decodeStatusListToken(
        from: cwtData,
        fetchedFrom: URL(string: sourceURL),
        clockSkew: clockSkew
      )
      
      return .success(claims)
      
    } catch {
      return .failure(.error(error.localizedDescription))
    }
  }
  
  private func processJWT(
    _ jwtData: Data,
    verifier: VerifyStatusListTokenSignature,
    sourceURL: String,
    format: StatusListTokenFormat,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    do {
      guard let jwt = String(data: jwtData, encoding: .utf8) else {
        return .failure(StatusError.invalidJWT)
      }
      
      // Use fresh date for each verification to prevent stale clock issues
      let currentDate = dateProvider()
      try await verifier.verify(
        statusListToken: jwtData,
        format: format,
        at: currentDate
      )

      let claims = try getAndEnsureClaims(
        jwt,
        sourceURL,
        currentDate,
        clockSkew
      )
      
      return .success(claims)
    } catch {
      return .failure(.error(error.localizedDescription))
    }
  }
  
  func getAndEnsureClaims(
    _ jwtString: String,
    _ uri: String,
    _ date: Date,
    _ clockSkew: TimeInterval
  ) throws -> StatusListTokenClaims {
    let jwt = try JWT(
      compactJWT: jwtString
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
    // Validate subject matches the fetch URL
    if uri != self.subject {
      throw StatusError.badSubject(self.subject)
    }

    // Validate iat is not in the future
    let iat = issuedAt
    let iatDate = Date(timeIntervalSince1970: iat)
    guard iatDate.addingTimeInterval(-clockSkew) <= date else {
      throw StatusError.invalidIssueDate
    }

    // Validate exp if present
    if let exp = expirationTime {
      let expirationDate = Date(timeIntervalSince1970: exp)
      guard date <= expirationDate.addingTimeInterval(clockSkew) else {
        throw StatusError.expiredToken
      }
    }

    // Enforce TTL if present: token age must not exceed ttl value
    // TTL defines maximum age from issuedAt, taking precedence over HTTP cache headers
    if let ttl = timeToLive {
      let tokenAge = date.timeIntervalSince1970 - iat
      guard tokenAge <= ttl + clockSkew else {
        throw StatusError.ttlExceeded
      }
    }

    return self
  }
}
