import AppKit
import CoreText
import SwiftUI

@MainActor
enum AppFontRegistry {
    struct FontResource: Equatable {
        let fileName: String
        let fileExtension: String
        let postScriptName: String
    }

    static let resources = [
        FontResource(fileName: "Geist[wght]", fileExtension: "ttf", postScriptName: "Geist-Regular"),
        FontResource(fileName: "GeistMono-Regular", fileExtension: "otf", postScriptName: "GeistMono-Regular"),
        FontResource(fileName: "InterVariable", fileExtension: "ttf", postScriptName: "InterVariable"),
    ]

    enum VariationAxis: String {
        case opticalSize = "opsz"
        case weight = "wght"

        var identifier: NSNumber {
            let value = rawValue.utf8.reduce(UInt32.zero) { partialResult, byte in
                (partialResult << 8) | UInt32(byte)
            }
            return NSNumber(value: value)
        }
    }

    private static var hasRegisteredFonts = false

    static func registerBundledFonts() {
        guard !hasRegisteredFonts else { return }

        for resource in resources {
            guard let url = applicationBundle.url(
                forResource: resource.fileName,
                withExtension: resource.fileExtension,
                subdirectory: "Fonts"
            ) else {
                preconditionFailure("Missing bundled font: \(resource.fileName).\(resource.fileExtension)")
            }

            var registrationError: Unmanaged<CFError>?
            guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registrationError) else {
                let message = registrationError?.takeRetainedValue().localizedDescription ?? "Unknown CoreText error"
                preconditionFailure("Unable to register \(resource.fileName).\(resource.fileExtension): \(message)")
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
        variations: [VariationAxis: CGFloat] = [:],
        openTypeFeatures: [String] = []
    ) -> Font {
        Font(nsFont(
            postScriptName: postScriptName,
            size: size,
            variations: variations,
            openTypeFeatures: openTypeFeatures
        ))
    }

    static func nsFont(
        postScriptName: String,
        size: CGFloat,
        variations: [VariationAxis: CGFloat] = [:],
        openTypeFeatures: [String] = []
    ) -> NSFont {
        registerBundledFonts()

        guard let baseFont = NSFont(name: postScriptName, size: size) else {
            preconditionFailure("Bundled font face is unavailable: \(postScriptName)")
        }

        var attributes: [NSFontDescriptor.AttributeName: Any] = [:]
        if !variations.isEmpty {
            attributes[.variation] = Dictionary(uniqueKeysWithValues: variations.map { axis, value in
                (axis.identifier, NSNumber(value: Double(value)))
            })
        }

        if !openTypeFeatures.isEmpty {
            attributes[NSFontDescriptor.AttributeName(kCTFontFeatureSettingsAttribute as String)] =
                openTypeFeatures.map { tag in
                    [
                        kCTFontOpenTypeFeatureTag as String: tag,
                        kCTFontOpenTypeFeatureValue as String: 1,
                    ] as [String: Any]
                }
        }

        guard !attributes.isEmpty else { return baseFont }
        let descriptor = baseFont.fontDescriptor.addingAttributes(attributes)

        guard let configuredFont = NSFont(descriptor: descriptor, size: size) else {
            preconditionFailure("Unable to configure bundled font: \(postScriptName)")
        }
        return configuredFont
    }

    private static var applicationBundle: Bundle {
        Bundle(for: FontBundleLocator.self)
    }
}

@MainActor
enum AppTypography {
    static let metricTracking: CGFloat = 0
    static let breakdownTracking: CGFloat = 0.1
    static let connectionTitleTracking: CGFloat = -0.16
    static let geistSlashedZeroFeatures = ["ss09"]
    static let interSlashedZeroFeatures = ["zero"]
    static let metricFeatures = interSlashedZeroFeatures + ["cv03", "cv02", "cv09"]

    static var geistRegular12: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 12,
            variations: [.weight: 400]
        )
    }

    static var geistMedium12: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 12,
            variations: [.weight: 450]
        )
    }

    static var geistRegular14: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 14,
            variations: [.weight: 400]
        )
    }

    static var geistSemibold16: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 16,
            variations: [.weight: 600]
        )
    }

    static var geistSelector12: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 12,
            variations: [.weight: 450]
        )
    }

    static var geistMetricLabel12: Font {
        AppFontRegistry.font(
            postScriptName: "Geist-Regular",
            size: 12,
            variations: [.weight: 450],
            openTypeFeatures: geistSlashedZeroFeatures
        )
    }

    static var geistMonoRegular11: Font {
        AppFontRegistry.font(postScriptName: "GeistMono-Regular", size: 11)
    }

    static var interComparison12: Font {
        AppFontRegistry.font(
            postScriptName: "InterVariable",
            size: 12,
            variations: [.opticalSize: 14, .weight: 450],
            openTypeFeatures: interSlashedZeroFeatures
        )
    }

    static var interDisplay48: Font {
        AppFontRegistry.font(
            postScriptName: "InterVariable",
            size: 48,
            variations: [.opticalSize: 32, .weight: 250],
            openTypeFeatures: metricFeatures
        )
    }
}

private final class FontBundleLocator: NSObject {}
