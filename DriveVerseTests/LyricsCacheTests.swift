import Testing
import Foundation
@testable import DriveVerse

@Suite struct LyricsCacheTests {
    private func makeCache(now: @escaping () -> Date) -> (LyricsCache, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("driveverse-cache-\(UUID().uuidString)")
        return (LyricsCache(directory: dir, now: now), dir)
    }

    @Test func roundTrip() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(.synced("[00:01.00]Hi"), signature: "song|artist|40")
        #expect(cache.lookup(signature: "song|artist|40") == .synced("[00:01.00]Hi"))
        #expect(cache.lookup(signature: "other|artist|40") == nil)
    }

    @Test func allResultKindsRoundTrip() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        for (i, result) in [LyricsFetchResult.plain("words"), .instrumental, .notFound].enumerated() {
            cache.store(result, signature: "sig-\(i)")
            #expect(cache.lookup(signature: "sig-\(i)") == result)
        }
    }

    @Test func expiresAfterThirtyDays() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let (cache, dir) = makeCache(now: { fakeNow })
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(.synced("x"), signature: "sig")
        fakeNow = fakeNow.addingTimeInterval(29 * 24 * 3600)
        #expect(cache.lookup(signature: "sig") == .synced("x"))
        fakeNow = fakeNow.addingTimeInterval(2 * 24 * 3600) // day 31
        #expect(cache.lookup(signature: "sig") == nil)
    }

    @Test func notFoundExpiresAfterOneDay() {
        var fakeNow = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let (cache, dir) = makeCache(now: { fakeNow })
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(.notFound, signature: "sig")
        fakeNow = fakeNow.addingTimeInterval(3600)
        #expect(cache.lookup(signature: "sig") == .notFound)
        fakeNow = fakeNow.addingTimeInterval(24 * 3600)
        #expect(cache.lookup(signature: "sig") == nil)
    }

    @Test func clearRemovesEverything() {
        let (cache, dir) = makeCache(now: Date.init)
        defer { try? FileManager.default.removeItem(at: dir) }

        cache.store(.synced("x"), signature: "a")
        cache.store(.plain("y"), signature: "b")
        cache.clear()
        #expect(cache.lookup(signature: "a") == nil)
        #expect(cache.lookup(signature: "b") == nil)
        // Cache still usable after clear.
        cache.store(.synced("z"), signature: "c")
        #expect(cache.lookup(signature: "c") == .synced("z"))
    }
}
