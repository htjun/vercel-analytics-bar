import AppKit
import CoreText
import SwiftUI

@MainActor
enum AppFontRegistry {
    struct FontResource: Equatable {
        let fileName: String
        let postScriptName: String
    }

    static let resources = [
        FontResource(fileName: "Geist-Regular", postScriptName: "Geist-Regular"),
        FontResource(fileName: "Geist-Medium", postScriptName: "Geist-Medium"),
        FontResource(fileName: "GeistMono-Regular", postScriptName: "GeistMono-Regular"),
        FontResource(fileName: "Inter-Medium", postScriptName: "Inter-Medium"),
        FontResource(fileName: "InterDisplay-Light", postScriptName: "InterDisplay-Light"),
    ]

    private static var hasRegisteredFonts = false

    static func registerBundledFonts() {
        guard !hasRegisteredFonts else { return }

        for resource in resources {
            guard let url = applicationBundle.url(
                forResource: resource.fileName,
                withExtension: "otf",
                subdirectory: "Fonts"
            ) else {
                preconditionFailure("Missing bundled font: \(resource.fileName).otf")
            }

            var registrationError: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) else {
                let message = registrationError?.takeRetainedValue().localizedDescription ?? "Unknown CoreText error"
                preconditionFailure("Unable to register \(resource.fileName).otf: \(message)")
            }
        }

        for resource in resources where NSFont(name: resource.postScriptName, size: 12) == nil {
            preconditionFailure("Registered font face is unavailable: \(resource.postScriptName)")
        }

        hasRegisteredFonts = true
    }

    static func font(
        postScriptName: String,
        size: CGFloat,
        openTypeFeatures: [String] = []
    ) -> Font {
        Font(nsFont(postScriptName: postScriptName, size: size, openTypeFeatures: openTypeFeatures))
    }

    static func nsFont(
        postScriptName: String,
        size: CGFloat,
        openTypeFeatures: [String] = []
    ) -> NSFont {
        registerBundledFonts()

        guard let baseFont = NSFont(name: postScriptName, size: size) else {
            preconditionFailure("Bundled font face is unavailable: \(postScriptName)")
        }
        guard !openTypeFeatures.isEmpty else { return baseFont }

        let settings = openTypeFeatures.map { tag in
            [
                kCTFontOpenTypeFeatureTag as String: tag,
                kCTFontOpenTypeFeatureValue as String: 1,
            ] as [String: Any]
        }
        let descriptor = baseFont.fontDescriptor.addingAttributes([
            NSFontDescriptor.AttributeName(kCTFontFeatureSettingsAttribute as String): settings,
        ])

        guard let featuredFont = NSFont(descriptor: descriptor, size: size) else {
            preconditionFailure("Unable to apply OpenType features to \(postScriptName)")
        }
        return featuredFont
    }

    private static var applicationBundle: Bundle {
        Bundle(for: FontBundleLocator.self)
    }
}

@MainActor
enum AppTypography {
    static let metricTracking: CGFloat = -1.44
    static let comparisonTracking: CGFloat = -0.48
    static let metricFeatures = ["zero", "cv03", "cv02", "cv09"]
    static let zeroFeature = ["zero"]

    static var geistRegular12: Font {
        AppFontRegistry.font(postScriptName: "Geist-Regular", size: 12)
    }

    static var geistMedium12: Font {
        AppFontRegistry.font(postScriptName: "Geist-Medium", size: 12)
    }

    static var geistMedium12WithSlashedZero: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Medium",
            size: 12,
            openTypeFeatures: zeroFeature
        )
    }

    static var interMedium12: Font {
        AppFontRegistry.font(
            postScriptName: "Inter-Medium",
            size: 12,
            openTypeFeatures: zeroFeature
        )
    }

    static var interDisplayLight48: Font {
        AppFontRegistry.font(
            postScriptName: "InterDisplay-Light",
            size: 48,
            openTypeFeatures: metricFeatures
        )
    }
}

private final class FontBundleLocator: NSObject {}
