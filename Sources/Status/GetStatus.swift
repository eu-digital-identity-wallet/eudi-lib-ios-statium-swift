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
import JOSESwift

import Foundation

/// A protocol that defines the necessary requirements for types that retrieve status information.
///
/// Conforming types are expected to provide a `VerifyStatusListTokenSignature`
/// and a `Date`, as well as a method to fetch a status asynchronously based on an index, session, format, and URL.
public protocol GetStatusType {
  
  /// Initializes an object that conforms to `GetStatusType` with the provided `verifier` and `date`.
  ///
  /// - Parameter verifier: An object responsible for verifying the status list token's signature.
  /// - Parameter decompressible: Used to decompress bytes.
  /// - Parameter date: The date used for token validation (e.g., to check expiration or issue time).
  ///
  /// This initializer is required to ensure the object is properly set up with the necessary dependencies
  /// for status retrieval and validation.
  init(
    verifier: any VerifyStatusListTokenSignature,
    decompressible: any DecompressibleType,
    date: Date
  )
  
  /// Fetches the status information asynchronously for a given index.
  ///
  /// This method retrieves the status for a specific index, given a URL session, token format, and URL.
  /// It performs an asynchronous operation and returns a result indicating either success (`Status`) or failure (`StatusError`).
  ///
  /// - Parameter index: The index of the status to retrieve.
  /// - Parameter session: The `URLSession` used to perform the network request.
  /// - Parameter format: The format of the status list token, represented as a `StatusListTokenFormat`.
  /// - Parameter url: A `URL` that represents the source of the status list.
  ///
  /// - Returns: A `Result` containing either a `Status` if the operation succeeds, or a `StatusError` if it fails.
  ///
  /// Example:
  /// ```swift
  /// let statusFetcher = GetStatus(verifier: yourVerifier, date: Date())
  /// let result = await statusFetcher.getStatus(index: 1, session: URLSession.shared, format: .jwt, url: yourURL)
  /// switch result {
  /// case .success(let status):
  ///     print(status)
  /// case .failure(let error):
  ///     print(error)
  /// }
  /// ```
  func getStatus(
    index: Int,
    session: URLSession,
    format: StatusListTokenFormat,
    url: URL
  ) async -> Result<Status, StatusError>
}


public actor GetStatus: GetStatusType {
  
  public let verifier: any VerifyStatusListTokenSignature
  public var decompressible: any DecompressibleType
  public let date: Date
  
  public init(
    verifier: any VerifyStatusListTokenSignature,
    decompressible: any DecompressibleType,
    date: Date = Date()
  ) {
    self.verifier = verifier
    self.decompressible = decompressible
    self.date = date
  }
  
  public func getStatus(
    index: Int,
    session: URLSession = .shared,
    format: StatusListTokenFormat = .jwt,
    url: URL
  ) async -> Result<Status, StatusError> {
    
    let result = await getStatusClaims(
      session: session,
      format: format,
      url: url
    )
    
    switch result {
    case .failure(let error):
      return .failure(error)
    case .success(let claims):
      guard
        let decodedBytes = Data.fromBase64URL(claims.statusList.compressedList)
      else {
        return .failure(.badBytes)
      }
      decompressible.setData(Data(decodedBytes))
      let decompressedBytes = decompressible.decompress()
      let statusByte = ReadStatus(
        bitsPerStatus: claims.statusList.bytesPerStatus,
        byteArray: [Byte](decompressedBytes)
      )
      
      if let byte = await statusByte.readStatus(at: index) {
        return .success(
          Status.fromByte(
            byte
          )
        )
      }
      return .failure(StatusError.badBytes)
    }
  }
}

private extension GetStatus {
  
  private func getStatusClaims(
    session: URLSession,
    format: StatusListTokenFormat,
    url: URL?
  ) async -> Result<StatusListTokenClaims, StatusError> {
    
    guard format == .jwt else { return .failure(.cwtNotSupported) }
    guard let url = url else { return .failure(.badUrl) }
    
    let jwtResult = await fetchJWT(from: url, session: session, format: format)
    
    switch jwtResult {
    case .failure(let error):
      return .failure(error)
    case .success(let jwt):
      return processJWT(
        jwt,
        verifier: verifier,
        sourceURL: url.absoluteString,
        format: format
      )
    }
  }
  
  private func fetchJWT(
    from url: URL,
    session: URLSession,
    format: StatusListTokenFormat
  ) async -> Result<String, StatusError> {
    
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue(format.fieldHeaderValue, forHTTPHeaderField: "Accept")
    
    do {
      let (data, response) = try await session.data(for: request)
      guard
        let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200
      else {
        return .failure(.networkError("Bad server response: \((response as? HTTPURLResponse)?.statusCode ?? -1)"))
      }
      
      guard let jwt = String(data: data, encoding: .utf8) else {
        return .failure(.decodingError("Failed to decode JWT from response"))
      }
      
      return .success(jwt)
      
    } catch {
      return .failure(.networkError(error.localizedDescription))
    }
  }
  
  private func processJWT(
    _ jwt: String,
    verifier: VerifyStatusListTokenSignature,
    sourceURL: String,
    format: StatusListTokenFormat
  ) -> Result<StatusListTokenClaims, StatusError> {
    do {
      let claims = try getAndEnsureClaims(jwt, sourceURL, date)
      try verifier.verify(statusListToken: jwt, format: format, at: date)
      
      return .success(claims)
    } catch {
      return .failure(.error(error.localizedDescription))
    }
  }
  
  func getAndEnsureClaims(
    _ jwt: String,
    _ uri: String,
    _ date: Date
  ) throws -> StatusListTokenClaims {
    let jws = try JWS(compactSerialization: jwt)
    let claims = try JSONDecoder().decode(
      StatusListTokenClaims.self,
      from: jws.payload.data()
    )
    
    if jws.header.typ != TokenStatusListSpec.mediaSubtypeStatusListJWT {
      throw StatusError.badJwtHeader
    }
    
    return try claims.ensureValid(uri: uri, date: date)
  }
}

extension StatusListTokenClaims {
  func ensureValid(uri: String, date: Date) throws -> StatusListTokenClaims {
    if uri != self.subject {
      throw StatusError.badSubject(self.subject)
    }
    
    let exp = expirationTime
    let expirationDate = Date(timeIntervalSince1970: exp)
    /*
     guard expirationDate > date else {
     throw StatusError.expiredToken
     }
     */
    
    let iat = issuedAt
    let iatDate = Date(timeIntervalSince1970: iat)
    /*
     guard iatDate <= date else {
     throw StatusError.invalidIssueDate
     }
     */
    
    return self
  }
}
