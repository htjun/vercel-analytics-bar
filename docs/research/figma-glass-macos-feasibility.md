# Reproducing Figma Glass in a Native macOS Menu-Bar App

Research snapshot: 2026-08-09

## Scope and evidence rule

This note evaluates how closely the pictured Figma Glass effect can be reproduced in this repository's native SwiftUI menu-bar app. The reference settings are: light angle `-45°`, light intensity `80%`, refraction `60`, depth `20`, dispersion `50`, frost `35`, and splay `0`.

Platform and design-tool facts are sourced only from Figma's official help and developer documentation, Apple's developer documentation and WWDC sessions, and the repository itself. Recommendations and implementation inferences are labeled as such.

## Executive verdict

The closest production result is a two-tier implementation:

1. On macOS 26 and later, use one system Liquid Glass surface (`NSGlassEffectView` or SwiftUI `glassEffect`) as the outer padded container, with the opaque white card embedded as its content. Prefer the `clear` variant for the highly transparent reference, no tint, a noninteractive resting surface, and the exact outer geometry from Figma.
2. On macOS 14 through 25, use `NSVisualEffectView` with `.underWindowBackground` and `.behindWindow`, then add a custom, noninteractive edge-artwork overlay for the diagonal specular highlight and subtle chromatic fringe. Put the same opaque white card above/in the center of that surface.

This will reproduce the overall impression closely—live desktop color, frost, a bright rounded edge, colored edge separation, and an opaque inset card—but it cannot reproduce Figma's numeric optical model exactly through public native material APIs. The public macOS 26 SwiftUI configuration consists of the `regular`, `clear`, and `identity` variants plus tint and interactivity; AppKit exposes `regular`/`clear`, tint, corner radius, content, and interactivity. Neither public surface exposes light angle/intensity, refraction amount, depth, chromatic dispersion, frost radius, or splay. [Apple: SwiftUI `Glass`](https://developer.apple.com/documentation/swiftui/glass) [Apple: `NSGlassEffectView`](https://developer.apple.com/documentation/appkit/nsglasseffectview) [Apple: `NSGlassEffectView.Style`](https://developer.apple.com/documentation/appkit/nsglasseffectview/style-swift.enum)

If pixel-level reproduction of those parameters against the actual desktop is mandatory, the technically legitimate route is to capture the relevant screen region with ScreenCaptureKit and process it with Metal/Core Image. That route requires Screen Recording permission and an `NSScreenCaptureUsageDescription`, which is disproportionate for decorative window chrome and should not be shipped for this app. [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) [Apple: macOS ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

## What Figma's controls actually describe

Figma describes Glass as a translucent effect that dynamically alters the objects beneath the layer. Its controls mean the following. [Figma: Apply effects to layers](https://help.figma.com/hc/en-us/articles/360041488473-Apply-effects-to-layers)

| Figma control | Figma definition | Reference value | Practical macOS interpretation |
| --- | --- | ---: | --- |
| Light angle | Direction from which light is projected | `-45°` | A diagonal edge highlight; on pre-26 systems draw this explicitly because native material lighting is system-owned. |
| Light intensity | Brightness of projected light | `80%` | A strong but narrow white specular edge. Do not treat `80%` as literal stroke opacity; calibrate visually. |
| Refraction | Optical distortion along the curved edge | `60` | macOS 26 Liquid Glass supplies adaptive lensing, but its strength is not public. Pre-26 material provides blur, not controllable lens distortion. |
| Depth | How far the curved edge extends inward; higher values appear more domed | `20` | Informs the perceived inner bevel. It does not directly equal the shell padding or an Apple API value. |
| Dispersion | Chromatic splitting along the curved edge | `50` | macOS 26 may create system-controlled color separation; pre-26 needs restrained cyan/warm edge artwork or a custom image filter. |
| Frost | Background blur on the glass | `35` | `NSVisualEffectView` supplies a semantic, system-controlled blur. It does not expose an arbitrary blur radius of 35. |
| Splay | Spread of projected light across the glass | `0` | Keep the highlight tight and omit a broad glow. |

The beta Figma Plugin API confirms that light intensity, refraction, and dispersion are normalized between `0` and `1`, while light angle is degrees, depth is a number greater than or equal to 1, and frost is represented as `radius`. The pictured UI values therefore correspond approximately to `lightIntensity: 0.8`, `lightAngle: -45`, `refraction: 0.6`, `depth: 20`, `dispersion: 0.5`, and `radius: 35`. The API is explicitly beta and subject to change. [Figma: `GlassEffect`](https://developers.figma.com/docs/plugins/api/Effect/#glasseffect) [Figma: Plugin API update 116](https://developers.figma.com/docs/plugins/updates/2025/07/17/version-1-update-116/)

There is an important handoff gap: Figma's current public `GlassEffect` schema contains no `splay` property even though the editor exposes that control. It also does not support variable binding. Record splay manually in the design specification instead of expecting Plugin API or generated code to preserve it. [Figma: `GlassEffect`](https://developers.figma.com/docs/plugins/api/Effect/#glasseffect)

Figma also documents these rendering limitations:

- Glass is invisible over a 100%-opaque fill.
- Glass cannot be combined with background blur on the same object; only the first effect in that visual layer renders.
- A background-blur object over a Glass object suppresses the Glass rendering.
- Glass-on-glass does not include the lower glass surface when rendering the upper one.
- Environmental reflections are not simulated.
- Glass is not supported in SVG export or Figma Sites.

These limitations mean the Figma result itself is a design approximation, not a portable physical-material specification. A raster export can be retained as a comparison reference, but it bakes a particular backdrop and is not a usable dynamic app material. [Figma: Apply effects to layers](https://help.figma.com/hc/en-us/articles/360041488473-Apply-effects-to-layers) [Figma: Export settings](https://developers.figma.com/docs/plugins/api/ExportSettings/)

## Native Liquid Glass on macOS 26+

### What the public APIs provide

SwiftUI's `glassEffect(_:in:)` places a system Liquid Glass shape behind the view and applies the material's foreground effects over the view. The material is anchored to the view's padded bounds, which naturally supports an outer container: size the opaque card, add the shell padding, then apply glass to the padded bounds. [Apple: `glassEffect(_:in:)`](https://developer.apple.com/documentation/swiftui/view/glasseffect%28_%3Ain%3A%29)

SwiftUI exposes these relevant choices:

- `.regular`, the standard adaptive variant;
- `.clear`, the permanently transparent variant, for which Apple recommends a dimming treatment when required for legibility;
- `.tint(...)`;
- `.interactive(...)`;
- an arbitrary `Shape` for the material boundary.

[Apple: `Glass`](https://developer.apple.com/documentation/swiftui/glass) [Apple: `Glass.clear`](https://developer.apple.com/documentation/swiftui/glass/clear) [Apple: `Glass.tint(_:)`](https://developer.apple.com/documentation/swiftui/glass/tint%28_%3A%29)

AppKit's `NSGlassEffectView` exposes the equivalent controls more directly for a custom panel: `contentView`, `cornerRadius`, `style` (`regular` or `clear`), `tintColor`, and interactive behavior. Apple says to assign the actual content through `contentView` so the framework can apply all treatments needed for legibility; placing a glass view behind content as an unrelated sibling is discouraged. Arbitrary extra subviews also have no guaranteed z-order relative to the content and glass effect. [Apple: Build an AppKit app with the new design, 18:13](https://developer.apple.com/videos/play/wwdc2025/310/?time=1093) [Apple: `NSGlassEffectView.contentView`](https://developer.apple.com/documentation/appkit/nsglasseffectview/contentview)

`NSGlassEffectContainerView`/`GlassEffectContainer` is for multiple nearby glass shapes that share sampling and merge or morph. The reference has one outer surface, so a glass container adds no value unless the redesign later introduces separate glass controls outside the white card. [Apple: Build an AppKit app with the new design, 19:35](https://developer.apple.com/videos/play/wwdc2025/310/?time=1175) [Apple: `GlassEffectContainer`](https://developer.apple.com/documentation/swiftui/glasseffectcontainer)

### Why it cannot be a literal translation of the Figma numbers

Apple describes Liquid Glass as a multi-layer, adaptive system whose tint, shadow, dynamic range, lensing, and refraction vary with the content beneath it, its size, and interaction. Larger shapes can appear optically thicker and receive stronger lensing and softer light scattering. This adaptivity is part of the material, so a native result is intentionally not a fixed rendering. [Apple: Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/)

The documented SwiftUI and AppKit property sets do not contain counterparts for Figma's seven optical sliders. Therefore:

- `clear` versus `regular` is a visual choice, not a mapping for frost `35` or refraction `60`.
- `tintColor = nil` is the best starting point for the screenshot's untinted shell, but it does not disable system adaptivity.
- Figma's `-45°` light cannot be imposed on native Liquid Glass.
- Figma's dispersion amount cannot be imposed on native Liquid Glass.

For this reference, start with `clear`, no tint, no interaction response on the decorative shell, the exact outer corner radius, and a 10–14 point inset to the opaque card. Compare `regular` only if `clear` loses too much separation on pale wallpapers. This is a visual recommendation, not an Apple-prescribed mapping.

## macOS 14–25: real backdrop frost, simulated optical edge

`NSVisualEffectView` is the correct public compatibility material. Apple explicitly documents that `.behindWindow` blends and blurs the desktop or other windows behind the app window. For the material, `.underWindowBackground` used with `.behindWindow` is intended to create a sense of looking through the back of the window; `.popover` is another semantic candidate because this app is a popover-like menu-bar surface. Test both, but choose based on the surface's purpose rather than a remembered color because Apple says materials change with system settings and should be selected semantically. [Apple: `NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview) [Apple: `.behindWindow`](https://developer.apple.com/documentation/appkit/nsvisualeffectview/blendingmode-swift.enum/behindwindow) [Apple: `.underWindowBackground`](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/underwindowbackground) [Apple: `.popover`](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/popover)

The compatibility shell should combine:

1. A masked `NSVisualEffectView` that fills the outer rounded rectangle.
2. A 10–14 point inset opaque white card that hides the material in the center.
3. A narrow white highlight stroke whose intensity varies around the perimeter with a `-45°`-aligned gradient.
4. Very low-opacity, subpixel-to-1-point cyan and warm/red edge strokes, clipped to the shell, to suggest dispersion.
5. A soft inner light/shadow pair extending roughly 2–4 points inward to suggest depth without pretending to refract the backdrop.
6. A normal window shadow outside the shell; no broad projected glow because splay is zero.

This is an approximation of the edge optics. `NSVisualEffectView` provides genuine live backdrop blur but does not expose a blur radius, refraction, or chromatic dispersion control. The overlay should stay subtle enough that it reads as light at the edge rather than as an RGB border.

## Can Core Animation background filters make it exact without capture permission?

Not for other apps' windows or the desktop, based on the public contract.

`CALayer.backgroundFilters` is a public macOS API that applies Core Image filters to content immediately behind a layer. Apple says that this content typically belongs to the layer's superlayer, and its example filters another layer in the same view hierarchy. Core Image publicly supplies Gaussian blur and distortion filters, including displacement, bump, glass, and lozenge distortions. This makes background filters useful for refracting known content rendered inside this app's layer tree. [Apple: `CALayer.backgroundFilters`](https://developer.apple.com/documentation/quartzcore/calayer/backgroundfilters) [Apple: Core Image distortion filters](https://developer.apple.com/documentation/coreimage/distortion-filters) [Apple: `CIGlassDistortion`](https://developer.apple.com/documentation/coreimage/ciglassdistortion)

However, Apple's `backgroundFilters` documentation does not say that the API receives the desktop or pixels from other processes. The only public API in this research that explicitly promises behind-window desktop/other-window sampling without screen capture is `NSVisualEffectView`, whose material rendering parameters are system-owned. There is also no documented guarantee that a custom background filter layered around an `NSVisualEffectView` can consume and spatially distort that private material result.

Consequently:

- A `CALayer.backgroundFilters` or custom Core Image prototype is reasonable for edge distortion of in-app content or a supplied backdrop image.
- It must not be presented as a supported way to refract arbitrary external-window pixels.
- It should not be the foundation of the production architecture unless a macOS 14–26 prototype proves stable and the effect remains correct across window moves, Spaces, Retina scale changes, accessibility settings, and OS updates.

This conclusion is deliberately narrower than saying the API can never happen to show a composited result. The public documentation does not grant the external sampling behavior required for a reliable implementation.

## The exact custom-rendering route and why not to ship it

An exact renderer needs an image of the scene behind the panel. Once that image exists, Metal or Core Image can implement:

- a signed-distance field for the outer and inner rounded rectangles;
- normal-based displacement concentrated in the edge band for refraction/depth;
- three slightly different sample coordinates for red, green, and blue dispersion;
- a Gaussian blur or multi-pass blur for frost;
- an analytic specular term for light angle, intensity, and splay;
- the opaque white card composited above the result.

Core Image's public displacement and glass filters demonstrate the image-processing primitives, although a custom kernel would be needed to reproduce Figma's rounded-rect edge model and channel separation precisely. [Apple: `CIDisplacementDistortion`](https://developer.apple.com/documentation/coreimage/cifilter/4401863-displacementdistortion) [Apple: `CIBumpDistortion`](https://developer.apple.com/documentation/coreimage/cifilter-swift.class/bumpdistortion%28%29)

To feed that renderer with the real desktop and other windows, ScreenCaptureKit requires the person's Screen Recording permission and an `NSScreenCaptureUsageDescription`. Apple's macOS sample prompts the first time and requires restart after permission is granted. This introduces privacy friction, capture lifecycle work, frame latency, GPU/energy cost, exclusion/feedback-loop handling, and failure states for a purely decorative effect. [Apple: ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit) [Apple: Capturing screen content in macOS](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos)

ScreenCaptureKit and Core Image are public APIs, so this approach is not inherently a private-API violation. It would still need to use each framework for its intended purpose, clearly disclose the capture behavior, and satisfy privacy review. Apple's App Review Guideline 2.5.1 requires public APIs and intended framework use. The recommendation against it is therefore product and privacy judgment, not a claim that custom screen rendering is categorically forbidden. [Apple: App Review Guidelines 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

Do not use private Core Animation backdrop filters, undocumented `CAFilter` names, window-server surfaces, or private AppKit classes to avoid the permission model. Mac App Store apps may only use public APIs. [Apple: App Review Guidelines 2.5.1](https://developer.apple.com/app-store/review/guidelines/#software-requirements)

## Recommended window architecture for this repository

The repository currently targets macOS 14 and uses `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Apple defines that style as a popover-like window for complex/data-rich menu-bar content. [`Base.xcconfig`](../../Config/Base.xcconfig) [`VercelAnalyticsBarApp.swift`](../../VercelAnalyticsBar/App/VercelAnalyticsBarApp.swift) [Apple: `MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra) [Apple: `WindowMenuBarExtraStyle`](https://developer.apple.com/documentation/swiftui/windowmenubarextrastyle)

### Phase 1: prove the rendering inside `MenuBarExtra`

First, keep `MenuBarExtra` and prototype the nested card:

- outer padded bounds use native Liquid Glass on macOS 26;
- macOS 14–25 use an `NSViewRepresentable` compatibility material;
- the existing content becomes one opaque white rounded card;
- edge artwork is an overlay and ignores pointer events.

This is the cheapest way to assess whether the system-owned popover window already supplies the correct silhouette and backdrop behavior. It avoids changing status-item presentation before the visual direction is validated.

### Phase 2: use a custom `NSPanel` only if shape control is insufficient

SwiftUI documents `MenuBarExtra.window` as a popover-like style but exposes no public API for its backing window's exact outer corner radius, background, arrow/chrome, or shadow. If the system surface cannot match the Figma silhouette, replace only the presentation layer with:

- `NSStatusItem` for the menu-bar trigger;
- a borderless, transparent `NSPanel`/`NSWindow` with `isOpaque = false`;
- one `NSGlassEffectView` on macOS 26 or one `NSVisualEffectView` on earlier systems;
- an `NSHostingView` for the existing SwiftUI card;
- explicit outside-click dismissal, status-item anchoring, screen-edge clamping, Spaces behavior, focus, and keyboard handling.

AppKit's public window APIs support a borderless style and transparent/nonopaque windows. A borderless window cannot normally become key or main without subclass behavior, so this route requires deliberate focus/accessibility engineering rather than just visual styling. [Apple: `NSWindow.StyleMask.borderless`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/borderless) [Apple: `NSWindow.isOpaque`](https://developer.apple.com/documentation/appkit/nswindow/isopaque) [Apple: `NSWindow`](https://developer.apple.com/documentation/appkit/nswindow)

The custom panel is the best long-term architecture if exact outer geometry is a design requirement. It is not required merely to add the inset card.

## Suggested parameter translation and calibration targets

These are starting values for a prototype, not mathematical equivalences:

| Visual property | macOS 26+ starting point | macOS 14–25 starting point |
| --- | --- | --- |
| Outer shape | Continuous rounded rectangle, about 30 pt radius | Same mask/radius |
| Shell inset | 10–14 pt | 10–14 pt |
| Inner card | Opaque dynamic light background, about 20–22 pt radius | Same |
| Material | `clear`, no tint; compare `regular` on pale backgrounds | `.underWindowBackground` + `.behindWindow`; compare `.popover` |
| Light `-45°`, intensity `80%` | Let native material light itself; optionally add only a faint corrective stroke if comparison requires it | Narrow diagonal white perimeter gradient, visually tuned rather than 0.8 literal alpha |
| Refraction `60`, depth `20` | Accept native adaptive lensing | 2–4 pt inner highlight/shadow cue; do not claim true refraction |
| Dispersion `50` | Accept native dispersion | Cyan and warm edge fringes offset no more than about 0.5–1 pt and kept at low opacity |
| Frost `35` | Native system frost | Semantic `NSVisualEffectView` blur; no numeric mapping |
| Splay `0` | Noninteractive resting shell, no added glow | No broad highlight bloom |

Validate at 1× and 2× display scale against at least four backdrops: pale neutral, dark neutral, high-frequency text/window content, and saturated wallpaper. Also test active/inactive appearance, light/dark mode, Increased Contrast, and Reduce Transparency. Apple says Liquid Glass changes with its environment and accessibility settings; `NSWorkspace.accessibilityDisplayShouldReduceTransparency` specifically instructs apps to use opaque windows when enabled. [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) [Apple: `accessibilityDisplayShouldReduceTransparency`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducetransparency)

For Reduce Transparency, replace the shell with an opaque or near-opaque neutral surface and retain a high-contrast outline. That accessibility fallback is more important than matching the reference screenshot.

## Final recommendation

Build a small visual prototype before the broader redesign:

1. Preserve the existing `MenuBarExtra` initially.
2. Make the white UI a single opaque rounded card inset 10–14 points.
3. Use macOS 26 native clear Liquid Glass around it with system-controlled optics.
4. Use `NSVisualEffectView(.underWindowBackground, .behindWindow)` plus carefully restrained edge artwork on macOS 14–25.
5. Move to a custom transparent `NSPanel` only if `MenuBarExtra` prevents the exact outer silhouette.
6. Do not request Screen Recording permission for decorative fidelity and do not use private backdrop-filter APIs.

This gives the closest dynamic result that remains native, privacy-preserving, App Store-compatible, adaptive, and maintainable. The native macOS 26 result will be physically richer than the fallback but not numerically identical to Figma; the fallback will match the still-image art direction while intentionally omitting true external-pixel refraction.
