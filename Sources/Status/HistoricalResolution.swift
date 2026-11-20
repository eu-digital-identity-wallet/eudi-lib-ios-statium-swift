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

/// Utilities for historical status list resolution (Draft 20 §8.4).
///
/// Historical resolution allows verifiers to check the status of a credential
/// at a specific point in time in the past, rather than just the current status.
///
/// ## Use Cases
/// - Audit trails: Verifying past transactions
/// - Legal disputes: Proving credential validity at time of use
/// - Delayed verification: Processing signed documents days after signing
public enum HistoricalResolution {

  /// Builds a URL with the time query parameter for historical resolution.
  ///
  /// - Parameters:
  ///   - baseURL: The base status list URL
  ///   - timestamp: The historical timestamp to query (Unix timestamp)
  /// - Returns: The URL with `?time=<timestamp>` appended, or nil if URL construction fails
  public static func buildHistoricalURL(baseURL: URL, timestamp: TimeInterval) -> URL? {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      return nil
    }

    // Format timestamp as ISO 8601 (Draft 20 §8.4 uses ISO 8601 format)
    let date = Date(timeIntervalSince1970: timestamp)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let isoTimestamp = formatter.string(from: date)

    // Add or update the time query parameter
    var queryItems = components.queryItems ?? []
    queryItems.removeAll { $0.name == TokenStatusListSpec.time }
    queryItems.append(URLQueryItem(name: TokenStatusListSpec.time, value: isoTimestamp))
    components.queryItems = queryItems

    return components.url
  }

  /// Validates that a status list token covers a requested historical timestamp.
  ///
  /// Draft 20 §8.4 requires: `iat ≤ requested_timestamp ≤ exp`
  ///
  /// This validation is crucial because a CDN or static server might ignore the
  /// `?time=` query parameter and return the latest status list instead of the
  /// historical one. This check catches such cases.
  ///
  /// - Parameters:
  ///   - claims: The status list token claims
  ///   - requestedTimestamp: The historical timestamp that was requested
  ///   - clockSkew: Allowed clock skew tolerance (default: 0)
  /// - Throws: `StatusError.historicalTimestampNotCovered` if the token doesn't cover the timestamp
  public static func validateTimestampCoverage(
    claims: StatusListTokenClaims,
    requestedTimestamp: TimeInterval,
    clockSkew: TimeInterval = 0
  ) throws {
    let iat = claims.issuedAt

    // iat ≤ requested_timestamp (with clock skew tolerance)
    guard iat - clockSkew <= requestedTimestamp else {
      throw StatusError.historicalTimestampNotCovered(
        requestedTime: requestedTimestamp,
        iat: iat,
        exp: claims.expirationTime
      )
    }

    // requested_timestamp ≤ exp (if exp is present, with clock skew tolerance)
    if let exp = claims.expirationTime {
      guard requestedTimestamp <= exp + clockSkew else {
        throw StatusError.historicalTimestampNotCovered(
          requestedTime: requestedTimestamp,
          iat: iat,
          exp: exp
        )
      }
    }
  }
}

// MARK: - Extended GetStatus API for Historical Resolution

extension GetStatus {
  /// Fetches the status information at a specific historical timestamp.
  public func getHistoricalStatus(
    index: Int,
    url: URL,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    historicalTimestamp: TimeInterval,
    referencedTokenExpiration: TimeInterval? = nil
  ) async -> Result<CredentialStatus, StatusError> {
    // Build the historical URL with time query parameter
    guard let historicalURL = HistoricalResolution.buildHistoricalURL(
      baseURL: url,
      timestamp: historicalTimestamp
    ) else {
      return .failure(.badUrl)
    }

    // Create a wrapper fetch handler that validates timestamp coverage
    let validatingFetchClaims: FetchClaimsHandler = { format, fetchURL, clockSkew in
      let result = await fetchClaims(format, fetchURL, clockSkew)

      switch result {
      case .success(let claims):
        // Validate that the returned token covers the requested timestamp
        do {
          try HistoricalResolution.validateTimestampCoverage(
            claims: claims,
            requestedTimestamp: historicalTimestamp,
            clockSkew: clockSkew
          )
          return .success(claims)
        } catch let error as StatusError {
          return .failure(error)
        } catch {
          return .failure(.error(error.localizedDescription))
        }
      case .failure(let error):
        // Check if it's a 404 indicating historical resolution not supported
        if case .error(let message) = error,
           message.contains("404") || message.lowercased().contains("not found") {
          return .failure(.historicalResolutionNotSupported)
        }
        return .failure(error)
      }
    }

    return await getStatus(
      index: index,
      url: historicalURL,
      format: format,
      fetchClaims: validatingFetchClaims,
      clockSkew: clockSkew,
      referencedTokenExpiration: referencedTokenExpiration
    )
  }

  /// Fetches the status information at a specific historical timestamp using a StatusReference.
  public func getHistoricalStatus(
    reference: StatusReference,
    format: StatusListTokenFormat = .jwt,
    fetchClaims: @escaping FetchClaimsHandler,
    clockSkew: TimeInterval,
    historicalTimestamp: TimeInterval,
    referencedTokenExpiration: TimeInterval? = nil
  ) async -> Result<CredentialStatus, StatusError> {
    await getHistoricalStatus(
      index: reference.idx,
      url: reference.uri,
      format: format,
      fetchClaims: fetchClaims,
      clockSkew: clockSkew,
      historicalTimestamp: historicalTimestamp,
      referencedTokenExpiration: referencedTokenExpiration
    )
  }
}
