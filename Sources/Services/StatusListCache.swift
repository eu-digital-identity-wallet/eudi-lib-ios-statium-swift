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

/// A cache entry for a status list token with computed expiration.
public struct CacheEntry: Sendable {
  /// The cached claims
  public let claims: StatusListTokenClaims
  /// When this cache entry expires (computed from TTL and exp)
  public let expiresAt: TimeInterval
  /// When this entry was fetched
  public let fetchedAt: TimeInterval

  /// Whether this cache entry is still valid
  /// - Parameter now: The current time
  /// - Parameter clockSkew: Allowed clock skew tolerance
  /// - Returns: true if the entry is still valid
  public func isValid(at now: TimeInterval, clockSkew: TimeInterval = 0) -> Bool {
    return now < expiresAt + clockSkew
  }
}

/// Protocol for status list caching.
///
/// Implementations should cache status list tokens according to Draft 20 §11.5:
/// - TTL (time-to-live) specifies how long the token can be cached from fetch time
/// - exp (expiration) is an absolute ceiling that overrides TTL
/// - The cache validity is the minimum of (fetch_time + TTL) and exp
public protocol StatusListCacheType: Sendable {
  /// Retrieves a cached entry for the given URL if it's still valid.
  /// - Parameter url: The status list URL
  /// - Returns: The cached claims if valid, nil otherwise
  func get(for url: URL) async -> StatusListTokenClaims?

  /// Stores claims in the cache with appropriate expiration.
  /// - Parameters:
  ///   - claims: The status list token claims to cache
  ///   - url: The URL these claims were fetched from
  ///   - fetchedAt: When the claims were fetched (for TTL calculation)
  func set(_ claims: StatusListTokenClaims, for url: URL, fetchedAt: TimeInterval) async

  /// Removes a cached entry for the given URL.
  /// - Parameter url: The URL to remove from cache
  func remove(for url: URL) async

  /// Clears all cached entries.
  func clear() async
}

/// An actor-based in-memory cache for status list tokens.
///
/// This cache implements the caching requirements from Draft 20 §11.5:
/// - Respects TTL claim for cache duration from fetch time
/// - Uses exp as an absolute ceiling regardless of TTL
/// - Automatically prunes expired entries on access
///
/// ## Example Usage
/// ```swift
/// let cache = StatusListCache()
/// let fetcher = CachingStatusListTokenFetcher(cache: cache, fetcher: underlyingFetcher)
/// ```
public actor StatusListCache: StatusListCacheType {

  private var storage: [String: CacheEntry] = [:]
  private let dateProvider: @Sendable () -> Date

  /// Creates a new cache instance.
  /// - Parameter dateProvider: A closure that provides the current date. Defaults to `Date()`.
  public init(dateProvider: @escaping @Sendable () -> Date = { Date() }) {
    self.dateProvider = dateProvider
  }

  public func get(for url: URL) async -> StatusListTokenClaims? {
    let key = url.absoluteString
    guard let entry = storage[key] else {
      return nil
    }

    let now = dateProvider().timeIntervalSince1970
    if entry.isValid(at: now) {
      return entry.claims
    } else {
      // Entry expired, remove it
      storage.removeValue(forKey: key)
      return nil
    }
  }

  public func set(_ claims: StatusListTokenClaims, for url: URL, fetchedAt: TimeInterval) async {
    let key = url.absoluteString
    let expiresAt = computeExpiration(claims: claims, fetchedAt: fetchedAt)

    let entry = CacheEntry(
      claims: claims,
      expiresAt: expiresAt,
      fetchedAt: fetchedAt
    )
    storage[key] = entry
  }

  public func remove(for url: URL) async {
    let key = url.absoluteString
    storage.removeValue(forKey: key)
  }

  public func clear() async {
    storage.removeAll()
  }

  /// Computes the cache expiration time based on Draft 20 §11.5 rules.
  ///
  /// The expiration is the minimum of:
  /// - fetch_time + TTL (if TTL is present)
  /// - exp (if present) - this is an absolute ceiling
  ///
  /// If neither TTL nor exp is present, the entry should not be cached (returns fetchedAt).
  private func computeExpiration(claims: StatusListTokenClaims, fetchedAt: TimeInterval) -> TimeInterval {
    var candidates: [TimeInterval] = []

    // TTL-based expiration: fetchedAt + ttl
    if let ttl = claims.timeToLive {
      candidates.append(fetchedAt + ttl)
    }

    // exp is an absolute ceiling
    if let exp = claims.expirationTime {
      candidates.append(exp)
    }

    // Return the minimum (most restrictive) expiration
    // If no constraints, don't cache (expire immediately)
    return candidates.min() ?? fetchedAt
  }

  /// Prunes expired entries from the cache.
  /// Call this periodically to free memory in long-running applications.
  public func prune() async {
    let now = dateProvider().timeIntervalSince1970
    storage = storage.filter { $0.value.isValid(at: now) }
  }
}

/// A caching wrapper for StatusListTokenFetcher that respects TTL and exp.
///
/// This fetcher checks the cache before making network requests and stores
/// successful responses in the cache according to Draft 20 §11.5 rules.
///
/// ## Usage
/// ```swift
/// let cache = StatusListCache()
/// let baseFetcher = StatusListTokenFetcher(networkingService: service, verifier: verifier)
/// let cachingFetcher = CachingStatusListTokenFetcher(
///   cache: cache,
///   networkingService: service,
///   verifier: verifier
/// )
/// ```
public actor CachingStatusListTokenFetcher: StatusListTokenFetcherType {

  private let cache: any StatusListCacheType
  private let underlying: StatusListTokenFetcher
  public nonisolated let dateProvider: @Sendable () -> Date

  /// Creates a caching fetcher.
  /// - Parameters:
  ///   - cache: The cache to use for storing status list tokens. Defaults to a new in-memory cache.
  ///   - networkingService: The networking service for HTTP requests
  ///   - verifier: The signature verifier for status list tokens
  ///   - dateProvider: A closure that provides the current date
  public init(
    cache: any StatusListCacheType = StatusListCache(),
    networkingService: NetworkingServiceType = NetworkingService(),
    verifier: any VerifyStatusListTokenSignature,
    dateProvider: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.cache = cache
    self.underlying = StatusListTokenFetcher(
      networkingService: networkingService,
      verifier: verifier,
      dateProvider: dateProvider
    )
    self.dateProvider = dateProvider
  }

  /// Protocol conformance initializer.
  public init(
    networkingService: NetworkingServiceType,
    verifier: any VerifyStatusListTokenSignature,
    dateProvider: @escaping @Sendable () -> Date
  ) {
    self.cache = StatusListCache(dateProvider: dateProvider)
    self.underlying = StatusListTokenFetcher(
      networkingService: networkingService,
      verifier: verifier,
      dateProvider: dateProvider
    )
    self.dateProvider = dateProvider
  }

  public func getStatusClaims(
    format: StatusListTokenFormat,
    url: URL,
    clockSkew: TimeInterval
  ) async -> Result<StatusListTokenClaims, StatusError> {
    // Check cache first
    if let cachedClaims = await cache.get(for: url) {
      return .success(cachedClaims)
    }

    // Cache miss - fetch from network
    let fetchedAt = dateProvider().timeIntervalSince1970
    let result = await underlying.getStatusClaims(format: format, url: url, clockSkew: clockSkew)

    // Cache successful results
    if case .success(let claims) = result {
      await cache.set(claims, for: url, fetchedAt: fetchedAt)
    }

    return result
  }

  /// Provides access to the cache for manual management (e.g., clearing, pruning).
  public var statusListCache: any StatusListCacheType {
    cache
  }
}
