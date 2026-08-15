import SwiftUI
import Testing
@testable import VercelAnalyticsBar

@Test func proportionalMetricTokensKeepPlaceValueIdentityAcrossCarries() {
    let before = ProportionalMetricToken.make(for: 999)
    let after = ProportionalMetricToken.make(for: 1006)

    #expect(before.map(\.text).joined() == "999")
    #expect(after.map(\.text).joined() == "1,006")
    #expect(Set(before.map(\.id)).intersection(after.map(\.id)) == Set([
        .digit(place: 0),
        .digit(place: 1),
        .digit(place: 2),
    ]))
    #expect(after.contains { $0.id == .digit(place: 3) })
    #expect(after.contains { $0.id == .grouping(digitsToRight: 3) })
    #expect(!ProportionalMetricText.rollsDown(from: 999, to: 1006))
    #expect(ProportionalMetricText.rollsDown(from: 1006, to: 999))
}

@MainActor
@Test func proportionalMetricLayoutUsesNaturalGlyphWidthsToMoveTheSuffix() throws {
    let before = ProportionalMetricToken.make(for: 819)
    let after = ProportionalMetricToken.make(for: 879)
    let beforeOffsets = ProportionalMetricLayout.leadingOffsets(for: before)
    let afterOffsets = ProportionalMetricLayout.leadingOffsets(for: after)
    let one = try #require(before.first { $0.id == .digit(place: 1) })
    let seven = try #require(after.first { $0.id == .digit(place: 1) })
    let unitID = ProportionalMetricToken.TokenID.digit(place: 0)
    let beforeUnitOffset = try #require(beforeOffsets[unitID])
    let afterUnitOffset = try #require(afterOffsets[unitID])
    let expectedDisplacement = ProportionalMetricLayout.width(for: seven)
        - ProportionalMetricLayout.width(for: one)

    #expect(abs(ProportionalMetricLayout.width(for: seven) - ProportionalMetricLayout.width(for: one)) > 0.1)
    #expect(abs((afterUnitOffset - beforeUnitOffset) - expectedDisplacement) < 0.001)
    #expect(ProportionalMetricText.frameWidth == 114)
    #expect(ProportionalMetricText.availableWidth == 160)
    #expect(ProportionalMetricText.frameHeight == 58)
    #expect(ProportionalMetricText.minimumScale == 0.7)
}

@MainActor
@Test func proportionalMetricScaleRemainsStableWhileDigitStructureIsUnchanged() {
    let narrowTokens = ProportionalMetricToken.make(for: 1111)
    let wideTokens = ProportionalMetricToken.make(for: 8888)

    #expect(ProportionalMetricLayout.naturalWidth(for: narrowTokens) !=
        ProportionalMetricLayout.naturalWidth(for: wideTokens))
    #expect(ProportionalMetricLayout.reservedWidth(for: narrowTokens) ==
        ProportionalMetricLayout.reservedWidth(for: wideTokens))
    #expect(ProportionalMetricText.scale(for: narrowTokens) ==
        ProportionalMetricText.scale(for: wideTokens))
    #expect(ProportionalMetricText.scale(for: narrowTokens) == 1)
}

@MainActor
@Test func proportionalMetricScaleShrinksOnlyWhenReservedWidthRunsOut() {
    let fittingTokens = ProportionalMetricToken.make(for: 9999)
    let overflowingTokens = ProportionalMetricToken.make(for: 999_999_999)

    #expect(ProportionalMetricText.scale(for: fittingTokens) == 1)
    #expect(ProportionalMetricText.scale(for: overflowingTokens) < 1)
    #expect(ProportionalMetricText.scale(for: overflowingTokens) >=
        ProportionalMetricText.minimumScale)
}
