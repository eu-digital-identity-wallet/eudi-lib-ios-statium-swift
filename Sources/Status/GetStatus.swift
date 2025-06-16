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

public typealias FetchClaimsHandler = @Sendable (URLSession, StatusListTokenFormat, URL, TimeInterval) async -> Result<StatusListTokenClaims, StatusError>

/// A protocol that defines the necessary requirements for types that retrieve status information.
///
/// Conforming types are expected to provide a `VerifyStatusListTokenSignature`
/// and a `Date`, as well as a method to fetch a status asynchronously based on an index, session, format, and URL.
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
  /// This method retrieves the status for a specific index, given a URL session, token format, and URL.
  /// It performs an asynchronous operation and returns a result indicating either success (`Status`) or failure (`StatusError`).
  ///
  /// - Parameter index: The index of the status to retrieve.
  /// - Parameter session: The `URLSession` used to perform the network request.
  /// - Parameter format: The format of the status list token, represented as a `StatusListTokenFormat`.
  /// - Parameter url: A `URL` that represents the source of the status list.
  /// - Parameter clockSkew: The time tolerance applied during status validation.
  /// - Parameter fetchClaims: A `FetchClaimsHandler` a caller can pass.
  ///
  /// - Returns: A `Result` containing either a `CredentialStatus` if the operation succeeds, or a `StatusError` if it fails.
  ///
  func getStatus(
    session: URLSession,
    index: Int,
    url: URL,
    format: StatusListTokenFormat,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval
  ) async -> Result<CredentialStatus, StatusError>
  
  func getStatus(
    session: URLSession,
    reference: StatusReference,
    format: StatusListTokenFormat,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval
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
    session: URLSession = .shared,
    index: Int,
    url: URL,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval
  ) async -> Result<CredentialStatus, StatusError> {
    
    let result = await fetchClaims(
      session,
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
        index: index
      )
    }
  }
  
  public func getStatus(
    session: URLSession = .shared,
    reference: StatusReference,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval
  ) async -> Result<CredentialStatus, StatusError> {
    await getStatus(
      session: session,
      index: reference.idx,
      url: reference.uri,
      format: format,
      fetchClaims: fetchClaims,
      clockSkew: clockSkew
    )
  }
  
  private func processStatusClaims(_ claims: StatusListTokenClaims, index: Int) async -> Result<CredentialStatus, StatusError> {
    guard let decodedBytes = Data.fromBase64URL(claims.statusList.compressedList) else {
      return .failure(.badBytes)
    }
    
    decompressible.setData(Data(decodedBytes))
    let decompressedBytes = decompressible.decompress()
    
    let statusByte = ReadStatus(
      bitsPerStatus: claims.statusList.bytesPerStatus,
      byteArray: [Byte](decompressedBytes)
    )
    
    if let byte = await statusByte.readStatus(at: index) {
      return .success(CredentialStatus.fromByte(byte))
    }
    
    return .failure(.badBytes)
  }
}
