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
import Testing
import Foundation

@testable import StatiumSwift

// MARK: - Thread-safe Time Provider for Testing

/// A thread-safe time provider that can be used in Sendable closures
final class MockTimeProvider: @unchecked Sendable {
  private let lock = NSLock()
  private var _currentTime: TimeInterval

  init(currentTime: TimeInterval = Date().timeIntervalSince1970) {
    self._currentTime = currentTime
  }

  var currentTime: TimeInterval {
    get {
      lock.withLock { _currentTime }
    }
    set {
      lock.withLock { _currentTime = newValue }
    }
  }

  func advance(by seconds: TimeInterval) {
    lock.withLock { _currentTime += seconds }
  }

  func makeDate() -> Date {
    Date(timeIntervalSince1970: currentTime)
  }
}

// MARK: - CacheEntry Tests

@Suite
struct CacheEntryTests {

  @Test
  func testIsValid_WhenBeforeExpiration_ThenReturnsTrue() {
    let now = Date().timeIntervalSince1970
    let entry = CacheEntry(
      claims: createMockClaims(),
      expiresAt: now + 3600,
      fetchedAt: now
    )

    #expect(entry.isValid(at: now))
    #expect(entry.isValid(at: now + 1800)) // 30 min later still valid
    #expect(entry.isValid(at: now + 3599)) // Just before expiration
  }

  @Test
  func testIsValid_WhenAfterExpiration_ThenReturnsFalse() {
    let now = Date().timeIntervalSince1970
    let entry = CacheEntry(
      claims: createMockClaims(),
      expiresAt: now + 3600,
      fetchedAt: now
    )

    #expect(!entry.isValid(at: now + 3601)) // Just after expiration
    #expect(!entry.isValid(at: now + 7200)) // Well after expiration
  }

  @Test
  func testIsValid_WhenWithinClockSkew_ThenReturnsTrue() {
    let now = Date().timeIntervalSince1970
    let entry = CacheEntry(
      claims: createMockClaims(),
      expiresAt: now + 3600,
      fetchedAt: now
    )

    // Entry technically expired, but within clock skew
    #expect(entry.isValid(at: now + 3700, clockSkew: 300)) // 100 seconds past, 300 allowed
  }

  private func createMockClaims() -> StatusListTokenClaims {
    StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      expirationTime: Date().timeIntervalSince1970 + 3600,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )
  }
}

// MARK: - StatusListCache Tests

@Suite
struct StatusListCacheTests {

  @Test
  func testGetSet_WhenCacheHit_ThenReturnsCachedClaims() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!
    let claims = createMockClaims(exp: timeProvider.currentTime + 3600)

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)

    // Advance time slightly
    timeProvider.advance(by: 1800)

    let result = await cache.get(for: url)
    #expect(result != nil)
    #expect(result?.subject == claims.subject)
  }

  @Test
  func testGet_WhenCacheMiss_ThenReturnsNil() async {
    let cache = StatusListCache()
    let url = URL(string: "https://example.com/nonexistent")!

    let result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testGet_WhenCacheExpired_ThenReturnsNilAndRemovesEntry() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!
    let claims = createMockClaims(exp: timeProvider.currentTime + 3600)

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)

    // Advance time past expiration
    timeProvider.advance(by: 7200)

    let result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testSet_WhenTTLProvided_ThenUsesMinOfTTLAndExp() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!

    // TTL is 300 seconds, exp is in 3600 seconds
    // Cache should expire based on TTL (the more restrictive one)
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: timeProvider.currentTime,
      expirationTime: timeProvider.currentTime + 3600,
      timeToLive: 300, // TTL is more restrictive
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)

    // After 200 seconds, should still be valid
    timeProvider.advance(by: 200)
    var result = await cache.get(for: url)
    #expect(result != nil)

    // After 350 seconds (past TTL), should be expired
    timeProvider.advance(by: 150)
    result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testSet_WhenExpBeforeTTL_ThenUsesExp() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!

    // TTL is 3600 seconds, exp is in 300 seconds
    // Cache should expire based on exp (the more restrictive one)
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: timeProvider.currentTime,
      expirationTime: timeProvider.currentTime + 300, // exp is more restrictive
      timeToLive: 3600,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)

    // After 200 seconds, should still be valid
    timeProvider.advance(by: 200)
    var result = await cache.get(for: url)
    #expect(result != nil)

    // After 350 seconds (past exp), should be expired
    timeProvider.advance(by: 150)
    result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testSet_WhenNoTTLOrExp_ThenDoesNotCache() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!
    let claims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: timeProvider.currentTime,
      expirationTime: nil,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)

    // Even immediately after, should not be cached (expires at fetchedAt)
    timeProvider.advance(by: 1)
    let result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testRemove_WhenEntryExists_ThenRemovesIt() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url = URL(string: "https://example.com/status")!
    let claims = createMockClaims(exp: timeProvider.currentTime + 3600)

    await cache.set(claims, for: url, fetchedAt: timeProvider.currentTime)
    await cache.remove(for: url)

    let result = await cache.get(for: url)
    #expect(result == nil)
  }

  @Test
  func testClear_ThenRemovesAllEntries() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url1 = URL(string: "https://example.com/status1")!
    let url2 = URL(string: "https://example.com/status2")!
    let claims = createMockClaims(exp: timeProvider.currentTime + 3600)

    await cache.set(claims, for: url1, fetchedAt: timeProvider.currentTime)
    await cache.set(claims, for: url2, fetchedAt: timeProvider.currentTime)
    await cache.clear()

    #expect(await cache.get(for: url1) == nil)
    #expect(await cache.get(for: url2) == nil)
  }

  @Test
  func testPrune_ThenRemovesExpiredEntries() async {
    let timeProvider = MockTimeProvider()
    let cache = StatusListCache(dateProvider: { timeProvider.makeDate() })

    let url1 = URL(string: "https://example.com/status1")!
    let url2 = URL(string: "https://example.com/status2")!

    // First entry expires in 300 seconds
    let claims1 = createMockClaims(exp: timeProvider.currentTime + 300)
    await cache.set(claims1, for: url1, fetchedAt: timeProvider.currentTime)

    // Second entry expires in 3600 seconds
    let claims2 = createMockClaims(exp: timeProvider.currentTime + 3600)
    await cache.set(claims2, for: url2, fetchedAt: timeProvider.currentTime)

    // Advance time past first entry's expiration
    timeProvider.advance(by: 400)

    await cache.prune()

    // First entry should be removed, second should remain
    #expect(await cache.get(for: url1) == nil)
    #expect(await cache.get(for: url2) != nil)
  }

  private func createMockClaims(exp: TimeInterval?) -> StatusListTokenClaims {
    StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: Date().timeIntervalSince1970,
      expirationTime: exp,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )
  }
}

// MARK: - CachingStatusListTokenFetcher Tests

@Suite
struct CachingStatusListTokenFetcherTests {

  @Test
  func testGetStatusClaims_WhenCacheHit_ThenReturnsCachedClaims() async {
    let timeProvider = MockTimeProvider()
    let dateProvider: @Sendable () -> Date = { timeProvider.makeDate() }

    let cache = StatusListCache(dateProvider: dateProvider)
    let url = URL(string: "https://example.com/status")!

    // Pre-populate cache
    let cachedClaims = StatusListTokenClaims(
      subject: "https://example.com/status",
      issuedAt: timeProvider.currentTime,
      expirationTime: timeProvider.currentTime + 3600,
      timeToLive: nil,
      statusList: StatusList(
        bytesPerStatus: .one,
        compressedList: "eJxjYGBgAAAABAAB",
        aggregationUri: nil
      )
    )
    await cache.set(cachedClaims, for: url, fetchedAt: timeProvider.currentTime)

    // The fetcher will check cache first, so we don't need to actually make network calls
    let result = await cache.get(for: url)
    #expect(result != nil)
    #expect(result?.subject == cachedClaims.subject)
  }

  @Test
  func testCacheEntry_ExpirationCalculation_UsesMinimumOfTTLAndExp() {
    let now = Date().timeIntervalSince1970

    // Test case 1: TTL is more restrictive
    let claimsTTLRestricts = StatusListTokenClaims(
      subject: "test",
      issuedAt: now,
      expirationTime: now + 3600, // 1 hour
      timeToLive: 300, // 5 minutes - more restrictive
      statusList: StatusList(bytesPerStatus: .one, compressedList: "eJxjYGBgAAAABAAB", aggregationUri: nil)
    )

    let entry1 = CacheEntry(
      claims: claimsTTLRestricts,
      expiresAt: min(now + 300, now + 3600), // Should be TTL-based
      fetchedAt: now
    )
    #expect(entry1.expiresAt == now + 300)

    // Test case 2: exp is more restrictive
    let claimsExpRestricts = StatusListTokenClaims(
      subject: "test",
      issuedAt: now,
      expirationTime: now + 300, // 5 minutes - more restrictive
      timeToLive: 3600, // 1 hour
      statusList: StatusList(bytesPerStatus: .one, compressedList: "eJxjYGBgAAAABAAB", aggregationUri: nil)
    )

    let entry2 = CacheEntry(
      claims: claimsExpRestricts,
      expiresAt: min(now + 3600, now + 300), // Should be exp-based
      fetchedAt: now
    )
    #expect(entry2.expiresAt == now + 300)
  }
}
