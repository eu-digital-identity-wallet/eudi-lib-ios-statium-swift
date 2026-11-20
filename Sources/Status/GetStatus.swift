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

public typealias FetchClaimsHandler = @Sendable (StatusListTokenFormat, URL, TimeInterval) async -> Result<StatusListTokenClaims, StatusError>

/// A protocol that defines the necessary requirements for types that retrieve status information.
///
/// Conforming types are expected to provide a `VerifyStatusListTokenSignature`
/// and a `Date`, as well as a method to fetch a status asynchronously based on an index, session, format, and URL.
///
/// ## Draft 20 §8.3: Pipeline Short-Circuit Requirement
///
/// **IMPORTANT:** Callers MUST validate the Referenced Token (the credential containing the status claim)
/// BEFORE calling any `getStatus` method. If the Referenced Token fails initial validation
/// (bad signature, expired `exp`, invalid claims, etc.), the verifier MUST NOT perform status
/// verification procedures. This means:
///
/// 1. Validate the Referenced Token's signature
/// 2. Validate the Referenced Token's expiration (`exp`) and other claims
/// 3. Only if validation passes, call `getStatus()` to check the status list
///
/// This library does not validate the Referenced Token itself - that responsibility lies with the caller.
/// The `referencedTokenExpiration` parameter is provided for the expiration precedence check
/// (Draft 20 §7.1), which ensures that even if the status list says VALID, an expired referenced
/// token is still treated as expired.
public protocol GetStatusType {

  /// Initializes an object that conforms to `GetStatusType`.
  ///
  /// - Parameter decompressible: Used to decompress bytes.
  ///
  /// This initializer is required to ensure the object is properly set up with the necessary dependencies
  /// for status retrieval and validation.
  init(
    decompressible: any DecompressibleType
  )

  /// Fetches the status information asynchronously for a given index.
  ///
  /// This method retrieves the status for a specific index, given a token format and URL.
  /// It performs an asynchronous operation and returns a result indicating either success (`Status`) or failure (`StatusError`).
  ///
  /// - Important: Per Draft 20 §8.3, the caller MUST validate the Referenced Token (signature, expiration, etc.)
  ///              BEFORE calling this method. Do not call this method if the Referenced Token is invalid.
  ///
  /// - Parameter index: The index of the status to retrieve.
  /// - Parameter format: The format of the status list token, represented as a `StatusListTokenFormat`.
  /// - Parameter url: A `URL` that represents the source of the status list.
  /// - Parameter clockSkew: The time tolerance applied during status validation.
  /// - Parameter fetchClaims: A `FetchClaimsHandler` a caller can pass.
  /// - Parameter referencedTokenExpiration: Optional expiration time of the referenced token.
  ///             Draft 20 §7.1: Even if status is VALID, if the referenced token's exp is past, it MUST be treated as expired.
  ///
  /// - Returns: A `Result` containing either a `CredentialStatus` if the operation succeeds, or a `StatusError` if it fails.
  ///
  func getStatus(
    index: Int,
    url: URL,
    format: StatusListTokenFormat,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    referencedTokenExpiration: TimeInterval?
  ) async -> Result<CredentialStatus, StatusError>

  func getStatus(
    reference: StatusReference,
    format: StatusListTokenFormat,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    referencedTokenExpiration: TimeInterval?
  ) async -> Result<CredentialStatus, StatusError>
}

public actor GetStatus: GetStatusType {

  public var decompressible: any DecompressibleType

  public init(
    decompressible: any DecompressibleType = Decompressible()
  ) {
    self.decompressible = decompressible
  }

  public func getStatus(
    index: Int,
    url: URL,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    referencedTokenExpiration: TimeInterval? = nil
  ) async -> Result<CredentialStatus, StatusError> {

    let result = await fetchClaims(
      format,
      url,
      clockSkew
    )

    switch result {
    case .failure(let error):
      return .failure(error)
    case .success(let claims):
      return await processStatusClaims(
        claims,
        index: index,
        referencedTokenExpiration: referencedTokenExpiration,
        clockSkew: clockSkew
      )
    }
  }

  public func getStatus(
    reference: StatusReference,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    referencedTokenExpiration: TimeInterval? = nil
  ) async -> Result<CredentialStatus, StatusError> {
    await getStatus(
      index: reference.idx,
      url: reference.uri,
      format: format,
      fetchClaims: fetchClaims,
      clockSkew: clockSkew,
      referencedTokenExpiration: referencedTokenExpiration
    )
  }
  
  private func processStatusClaims(
    _ claims: StatusListTokenClaims,
    index: Int,
    referencedTokenExpiration: TimeInterval?,
    clockSkew: TimeInterval
  ) async -> Result<CredentialStatus, StatusError> {
    guard let decodedBytes = Data.fromBase64URL(claims.statusList.compressedList) else {
      return .failure(.badBytes)
    }

    decompressible.setData(Data(decodedBytes))
    let decompressedBytes = decompressible.decompress()

    let statusReader = ReadStatus(
      bitsPerStatus: claims.statusList.bytesPerStatus,
      byteArray: [Byte](decompressedBytes)
    )

    do {
      let byte = try await statusReader.readStatus(at: index)
      let status = CredentialStatus.fromByte(byte)

      // Draft 20 §7.1: Expiration Precedence
      // Even if the status list says VALID (0x00), if the Referenced Token's own exp
      // is in the past, the token MUST evaluate as expired.
      if status == .valid, let exp = referencedTokenExpiration {
        let now = Date().timeIntervalSince1970
        if exp < now - clockSkew {
          return .failure(.expiredToken)
        }
      }

      return .success(status)
    } catch let error as StatusError {
      return .failure(error)
    } catch {
      return .failure(.badBytes)
    }
  }
}
