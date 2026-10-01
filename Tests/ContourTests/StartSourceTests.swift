import Foundation
import Testing

@testable import Contour

struct StartSourceTests {
    @Test func everySourceRoundTripsThroughItsStorageKey() {
        for source in [StartSource.reviewRequests, .recents, .watched("acme/api")] {
            #expect(StartSource(storageKey: source.storageKey) == source)
        }
    }

    @Test func storageKeysAreStableStrings() {
        #expect(StartSource.reviewRequests.storageKey == "reviewRequests")
        #expect(StartSource.recents.storageKey == "recents")
        #expect(StartSource.watched("acme/api").storageKey == "watched:acme/api")
    }

    @Test func unknownOrEmptyStorageKeysDecodeToNothing() {
        #expect(StartSource(storageKey: "") == nil)
        #expect(StartSource(storageKey: "settings") == nil)
        #expect(StartSource(storageKey: "watched:") == nil)
    }
}
