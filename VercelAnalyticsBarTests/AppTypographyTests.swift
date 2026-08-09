import AppKit
import CoreText
import Testing
@testable import VercelAnalyticsBar

@MainActor
@Test func bundledFontsRegisterWithExpectedPostScriptNames() {
    AppFontRegistry.registerBundledFonts()

    for resource in AppFontRegistry.resources {
        #expect(NSFont(name: resource.postScriptName, size: 12) != nil)
    }
}

@MainActor
@Test func geistVariableFontSupportsEveryPlannedWeight() {
    for weight: CGFloat in [400, 450, 500] {
        let font = AppFontRegistry.nsFont(
            postScriptName: "Geist-Regular",
            size: 12,
            variations: [.weight: weight]
        )

        #expect(font.familyName == "Geist")
        #expect(font.pointSize == 12)
        #expect(resolvedVariationValue(.weight, in: font) == weight)
    }
}

@MainActor
@Test func geistVariableFontCombinesWeightAndOpenTypeFeatures() {
    let font = AppFontRegistry.nsFont(
        postScriptName: "Geist-Regular",
        size: 12,
        variations: [.weight: 500],
        openTypeFeatures: AppTypography.geistSlashedZeroFeatures
    )

    #expect(resolvedVariationValue(.weight, in: font) == 500)
    #expect(openTypeFeatureTags(in: font) == Set(["ss09"]))
}

@MainActor
@Test func variableFontsExposeExpectedAxisRanges() {
    let geist = AppFontRegistry.nsFont(postScriptName: "Geist-Regular", size: 12)
    let inter = AppFontRegistry.nsFont(postScriptName: "InterVariable", size: 12)

    #expect(variationRange(.weight, in: geist) == 100 ... 900)
    #expect(variationRange(.weight, in: inter) == 100 ... 900)
    #expect(variationRange(.opticalSize, in: inter) == 14 ... 32)
}

@MainActor
@Test func interVariableFontsResolvePlannedAxesAndFeatures() {
    let comparisonFont = AppFontRegistry.nsFont(
        postScriptName: "InterVariable",
        size: 12,
        variations: [.opticalSize: 14, .weight: 500],
        openTypeFeatures: AppTypography.interSlashedZeroFeatures
    )
    let metricFont = AppFontRegistry.nsFont(
        postScriptName: "InterVariable",
        size: 48,
        variations: [.opticalSize: 32, .weight: 300],
        openTypeFeatures: AppTypography.metricFeatures
    )

    #expect(comparisonFont.familyName == "Inter Variable")
    #expect(comparisonFont.pointSize == 12)
    #expect(resolvedVariationValue(.weight, in: comparisonFont) == 500)
    #expect(resolvedVariationValue(.opticalSize, in: comparisonFont) == 14)
    #expect(openTypeFeatureTags(in: comparisonFont) == Set(["zero"]))

    #expect(metricFont.familyName == "Inter Variable")
    #expect(metricFont.pointSize == 48)
    #expect(resolvedVariationValue(.weight, in: metricFont) == 300)
    #expect(resolvedVariationValue(.opticalSize, in: metricFont) == 32)
    #expect(openTypeFeatureTags(in: metricFont) == Set(["zero", "cv02", "cv03", "cv09"]))
    #expect(AppTypography.comparisonTracking == -0.48)
    #expect(AppTypography.metricTracking == -1.44)
}

private func resolvedVariationValue(_ axis: AppFontRegistry.VariationAxis, in font: NSFont) -> CGFloat? {
    let variations = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber]
    if let value = variations?[axis.identifier] {
        return CGFloat(truncating: value)
    }

    let axes = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]]
    let matchingAxis = axes?.first { axisDescription in
        (axisDescription[kCTFontVariationAxisIdentifierKey] as? NSNumber) == axis.identifier
    }
    return (matchingAxis?[kCTFontVariationAxisDefaultValueKey] as? NSNumber).map(CGFloat.init(truncating:))
}

private func variationRange(
    _ axis: AppFontRegistry.VariationAxis,
    in font: NSFont
) -> ClosedRange<CGFloat>? {
    let axes = CTFontCopyVariationAxes(font as CTFont) as? [[CFString: Any]]
    guard let matchingAxis = axes?.first(where: { axisDescription in
        (axisDescription[kCTFontVariationAxisIdentifierKey] as? NSNumber) == axis.identifier
    }),
        let minimum = matchingAxis[kCTFontVariationAxisMinimumValueKey] as? NSNumber,
        let maximum = matchingAxis[kCTFontVariationAxisMaximumValueKey] as? NSNumber
    else {
        return nil
    }

    return CGFloat(truncating: minimum) ... CGFloat(truncating: maximum)
}

private func openTypeFeatureTags(in font: NSFont) -> Set<String> {
    let featureKey = NSFontDescriptor.AttributeName(kCTFontFeatureSettingsAttribute as String)
    let settings = font.fontDescriptor.object(forKey: featureKey) as? [[String: Any]]
    return Set(settings?.compactMap { $0[kCTFontOpenTypeFeatureTag as String] as? String } ?? [])
}
