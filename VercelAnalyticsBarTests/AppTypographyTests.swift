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
    for weight: CGFloat in [400, 450, 600] {
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
@Test func connectionTypographyMatchesTheReferenceFrame() {
    let body = AppFontRegistry.nsFont(
        postScriptName: "Geist-Regular",
        size: 14,
        variations: [.weight: 400]
    )
    let title = AppFontRegistry.nsFont(
        postScriptName: "Geist-Regular",
        size: 16,
        variations: [.weight: 600]
    )

    #expect(body.pointSize == 14)
    #expect(resolvedVariationValue(.weight, in: body) == 400)
    #expect(title.pointSize == 16)
    #expect(resolvedVariationValue(.weight, in: title) == 600)
    #expect(AppTypography.connectionTitleTracking == -0.16)
}

@MainActor
@Test func geistVariableFontCombinesWeightAndOpenTypeFeatures() {
    let font = AppFontRegistry.nsFont(
        postScriptName: "Geist-Regular",
        size: 12,
        variations: [.weight: 450],
        openTypeFeatures: AppTypography.geistSlashedZeroFeatures
    )

    #expect(resolvedVariationValue(.weight, in: font) == 450)
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
        variations: [.opticalSize: 14, .weight: 450],
        openTypeFeatures: AppTypography.interSlashedZeroFeatures
    )
    let metricFont = AppFontRegistry.nsFont(
        postScriptName: "InterVariable",
        size: 48,
        variations: [.opticalSize: 32, .weight: 250],
        openTypeFeatures: AppTypography.metricFeatures
    )

    #expect(comparisonFont.familyName == "Inter Variable")
    #expect(comparisonFont.pointSize == 12)
    #expect(resolvedVariationValue(.weight, in: comparisonFont) == 450)
    #expect(resolvedVariationValue(.opticalSize, in: comparisonFont) == 14)
    #expect(openTypeFeatureTags(in: comparisonFont) == Set(["zero"]))

    #expect(metricFont.familyName == "Inter Variable")
    #expect(metricFont.pointSize == 48)
    #expect(resolvedVariationValue(.weight, in: metricFont) == 250)
    #expect(resolvedVariationValue(.opticalSize, in: metricFont) == 32)
    #expect(openTypeFeatureTags(in: metricFont) == Set(["zero", "cv02", "cv03", "cv09", "ss03"]))
    #expect(AppTypography.metricTracking == 0)
}

@MainActor
@Test func numberStyleMapsInterAxesAndOpenTypeFeatures() throws {
    let defaultStyle = NumberStyle.default
    let defaultFont = defaultStyle.nsFont
    let squareCommaStyle = try NumberStyle(
        color: .rgb(red: 38, green: 38, blue: 38),
        fontSize: 64,
        fontWeight: 375,
        opticalSize: 20,
        tracking: -0.25,
        commaStyle: .square,
        slashedZero: false,
        openFour: false,
        openSix: true,
        flatTopThree: false,
        animationDuration: 1.25,
        animationEasing: .easeInOut
    )
    let squareCommaFont = squareCommaStyle.nsFont

    #expect(resolvedVariationValue(.weight, in: defaultFont) == 280)
    #expect(resolvedVariationValue(.opticalSize, in: defaultFont) == 32)
    #expect(openTypeFeatureTags(in: defaultFont) == Set(["zero", "cv02", "cv03", "cv09", "ss07"]))

    #expect(squareCommaFont.pointSize == 64)
    #expect(resolvedVariationValue(.weight, in: squareCommaFont) == 375)
    #expect(resolvedVariationValue(.opticalSize, in: squareCommaFont) == 20)
    #expect(openTypeFeatureTags(in: squareCommaFont) == Set(["cv03", "ss07"]))
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
