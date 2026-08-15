# macOS Distribution Research

Research date: 2026-08-15

## Recommendation

Ship the first public version directly as a signed and notarized DMG attached to a GitHub Release.
Use a small static website only as the product front door; keep the binary on GitHub Releases and
link the website's Download button to it. Defer the Mac App Store and Sparkle until the direct release
process has been exercised manually at least once.

This is a good fit for a free, open-source hobby project:

- Developer ID distribution avoids App Review while still giving users the normal Gatekeeper trust
  flow. Apple defines Developer ID specifically for Mac software distributed outside the Mac App
  Store, and a notarization ticket lets Gatekeeper verify that Apple found no known malware and that
  the software was not altered. [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- GitHub Releases is intended to bundle source versions, release notes, and downloadable binaries.
  Each asset may be up to 2 GiB, with no total release-size or release-bandwidth limit, which is ample
  for this app. [GitHub: About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
- A DMG is a better public installer for this single-bundle app than a PKG. Apple says a signed DMG
  protects all included files and is an easy experience for a single file or bundle; PKG is best when
  a product has multiple components, needs specific install locations, or runs installation code.
  [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

The project's nonprofit or hobby status does not change Apple's signing and notarization steps.

## Current repository assessment

The repository already has the important product-side release foundations:

- `Release-Direct` and `Release-AppStore` configurations exist, and the shared scheme's Archive
  action uses `Release-Direct`.
- `Release-Direct` enables the Hardened Runtime and removes the Debug-only Chart Inspector and demo
  code.
- The app is a universal `arm64` + `x86_64` build with a macOS 14 minimum.
- The app uses App Sandbox with only outgoing network access and a canonical Keychain access group.
- Version metadata is centralized in `Config/Base.xcconfig` (`MARKETING_VERSION = 0.1.0`,
  `CURRENT_PROJECT_VERSION = 1`).
- The existing GitHub Actions workflow verifies `main`, but there is no release workflow, release
  packaging, updater, or appcast yet.

There is one immediate configuration gap: `Debug.xcconfig` optionally includes the ignored
`Local.xcconfig`, but neither release xcconfig currently does, and the project file has no
`DEVELOPMENT_TEAM`. The existing verification builds explicitly disable signing, so they do not
exercise this gap. Before the first archive, supply the release team deterministically: either add a
release-only optional local signing include, select and persist the team in Xcode, or pass
`DEVELOPMENT_TEAM=TEAM_ID` (and provisioning-update permission when appropriate) to the archive
command. A release should fail if no team is supplied; do not fall back to an ad-hoc signature.

The Hardened Runtime setting is already correct. Apple requires it for notarization and recommends
adding only the runtime exceptions an app actually needs. This app currently claims no runtime
exceptions. [Apple: Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)

### Important signing check: the Keychain entitlement

`keychain-access-groups` is a restricted entitlement on macOS. Unlike App Sandbox and Hardened
Runtime entitlements, it must be authorized by a provisioning profile. Apple specifically uses
Keychain access groups as its example of why a macOS app sometimes needs a profile even though Mac
code generally does not. [Apple TN3125: Inside Code Signing — Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)

For the direct build:

1. Register the explicit App ID `com.jasonjun.VercelAnalyticsBar` under the long-term Apple team.
2. Let Xcode automatic signing create the Developer ID distribution assets during Archive/Export,
   or manually create a Developer ID distribution profile for the same App ID.
3. Confirm the exported app contains `Contents/embedded.provisionprofile` and that its allow-list
   authorizes the app's Team-ID-prefixed Keychain group. Apple's distribution-signing guidance says
   a distribution profile must be placed in the bundle when an app claims a restricted entitlement,
   and names `keychain-access-groups` specifically. [Apple: Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac)

Do not remove the entitlement just to make export easier: the app deliberately uses the canonical
group for stable Data Protection Keychain access. Instead, make the distribution profile part of
the release invariant and test credential continuity during upgrades.

## First-release process

### 1. Freeze identity and release metadata

- Keep the bundle identifier stable. Changing the App ID prefix or bundle identifier later can make
  existing Keychain items inaccessible.
- Update `MARKETING_VERSION` for the human version and monotonically increment
  `CURRENT_PROJECT_VERSION` for every uploaded build.
- Make a release from a clean commit that passed `Scripts/verify.sh`.
- Use a version tag such as `v0.1.0`; push the tag before publishing the release. GitHub CLI can
  refuse to publish if the remote tag is missing with `--verify-tag` and can generate release notes
  with `--generate-notes`. [GitHub CLI: `gh release create`](https://cli.github.com/manual/gh_release_create)

### 2. Create the signing assets once

- Create a **Developer ID Application** certificate and retain its private key securely. That is the
  certificate for an app and for a DMG. A **Developer ID Installer** certificate is only needed if a
  PKG is shipped. [Apple: Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- Store notarization credentials in the Keychain rather than in a script:

  ```sh
  xcrun notarytool store-credentials "VercelAnalyticsBar-notary" \
    --apple-id "APPLE_ID" \
    --team-id "TEAM_ID" \
    --password "APP_SPECIFIC_PASSWORD"
  ```

  `notarytool` supports this Keychain-profile flow so the password does not have to appear in later
  scripts. [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)

### 3. Archive and export the signed app

For the first release, use Xcode's Organizer because it exposes signing mistakes clearly:

1. Select **Any Mac** as the destination and choose **Product > Archive**.
2. In Organizer, choose **Distribute App > Developer ID** and export a Developer-ID-signed app.
3. Save the generated `ExportOptions.plist`; it becomes the basis for a later reproducible
   `xcodebuild -exportArchive` step.
4. Inspect the exported app before packaging:

   ```sh
   codesign --verify --deep --strict --verbose=2 "VercelAnalyticsBar.app"
   codesign --display --verbose=4 "VercelAnalyticsBar.app"
   codesign --display --entitlements - --xml "VercelAnalyticsBar.app"
   security cms -D -i "VercelAnalyticsBar.app/Contents/embedded.provisionprofile"
   ```

The signature output should identify **Developer ID Application**, include a secure timestamp and
the Runtime flag, omit `com.apple.security.get-task-allow`, and show the expected sandbox, network,
and Keychain entitlements. Apple requires Developer ID signing, Hardened Runtime, a secure timestamp,
and no distribution `get-task-allow` entitlement for notarization. [Apple: Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)

### 4. Build, sign, notarize, and staple the DMG

Create a simple read-only `UDZO` DMG containing the app and an Applications-folder symlink. A custom
background can wait; correct signing and a clear drag-to-Applications layout matter more. Use
`ditto` when copying app bundles because it preserves symlinks. Apple documents `hdiutil` for DMG
creation and says the final image should be signed with the Developer ID Application identity and a
secure timestamp. [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

Then submit the exact outermost file that users will download:

```sh
xcrun notarytool submit "VercelAnalyticsBar-0.1.0.dmg" \
  --keychain-profile "VercelAnalyticsBar-notary" \
  --wait

xcrun stapler staple "VercelAnalyticsBar-0.1.0.dmg"
xcrun stapler validate "VercelAnalyticsBar-0.1.0.dmg"
```

Always retrieve and inspect the notarization log, even when the status is `Accepted`; Apple notes
that accepted submissions may still contain warnings worth fixing. Notarize only the outermost
container when using nested signed containers. Stapling matters because it allows Gatekeeper to
verify the ticket even when a user's Mac is offline. [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

### 5. Verify the final download, not just the build folder

Run mechanical checks against the final image and its mounted app:

```sh
hdiutil verify "VercelAnalyticsBar-0.1.0.dmg"
xcrun stapler validate "VercelAnalyticsBar-0.1.0.dmg"
   codesign --verify --deep --strict --verbose=2 "/Volumes/Vercel Analytics Bar/VercelAnalyticsBar.app"
   spctl --assess --type exec --verbose=4 "/Volumes/Vercel Analytics Bar/VercelAnalyticsBar.app"
```

`spctl` should report `source=Notarized Developer ID`. Apple recommends `codesign` and `spctl` for
preflight checks, but also says they are not exhaustive. The decisive test is to download the
packaged app so macOS applies quarantine, install it in `/Applications`, and launch it through the
real Gatekeeper flow. [Apple: Code Signing Tasks](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html)

Prefer a different Mac, clean macOS VM, or at least a fresh macOS user account. Apple's packaging
test matrix includes fresh install, upgrade, duplicate copies, a different installer account, run
from the DMG, and run after moving the app. [Apple: Packaging Mac software for distribution](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution)

For this app, add product-specific release checks:

- Connect a Vercel account in the old version, replace it with the new version, and verify the token
  remains accessible. This catches provisioning-profile or Keychain-group regressions.
- Verify disconnect removes the credential and cached data.
- Verify launch-at-login only after explicit consent and survives an upgrade.
- Verify an Intel Mac if practical; otherwise at least inspect the universal binary with `lipo -info`.
- Verify the menu-bar-only launch experience from a fresh account because there is no Dock icon.

Never tell users to bypass Gatekeeper or delete quarantine attributes as the normal installation
path. Treat that need as a release defect.

### 6. Publish a GitHub Release

Attach at least:

- `VercelAnalyticsBar-0.1.0.dmg`
- `VercelAnalyticsBar-0.1.0.dmg.sha256`
- release notes with the macOS requirement, install steps, major changes, known issues, and the
  source tag/commit

Create the checksum from the final, stapled file:

```sh
shasum -a 256 "VercelAnalyticsBar-0.1.0.dmg" \
  > "VercelAnalyticsBar-0.1.0.dmg.sha256"
```

The Apple code signature and notarization are the primary trust controls. The checksum is still
useful for download-integrity checks and mirrors. If the repository enables immutable releases,
create a draft, attach every asset, verify it, and only then publish; GitHub prevents published
immutable release tags and assets from being modified or deleted. [GitHub CLI: `gh release create`](https://cli.github.com/manual/gh_release_create)

For a website's stable Download button, either link to the release page:

```text
https://github.com/htjun/vercel-analytics-bar/releases/latest
```

or keep a constant uploaded asset name such as `VercelAnalyticsBar.dmg` and link directly:

```text
https://github.com/htjun/vercel-analytics-bar/releases/latest/download/VercelAnalyticsBar.dmg
```

GitHub officially supports both latest-release and latest-asset URLs. The direct asset URL only
remains stable when every release uses exactly the same asset name. [GitHub: Linking to releases](https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases)

## Where the website and downloads should live

Keep the concerns separate:

| Concern | Recommended home |
| --- | --- |
| Source, issues, tags, release notes | Existing GitHub repository |
| Versioned DMG and checksum | GitHub Releases |
| Marketing page, install guide, privacy statement | GitHub Pages initially, or any static host later |
| Future Sparkle appcast | Static HTTPS site, with enclosure URLs pointing to versioned GitHub Release assets |

GitHub Pages is enough for a small open-source product page and supports custom apex domains and
subdomains. [GitHub: About custom domains and GitHub Pages](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/about-custom-domains-and-github-pages)
Do not put DMGs in the Pages deployment: Pages has a 1 GiB published-site limit and a soft 100 GiB
monthly bandwidth limit, and GitHub itself recommends Releases when a site exceeds these quotas.
[GitHub: GitHub Pages limits](https://docs.github.com/en/pages/getting-started-with-github-pages/github-pages-limits)

The site does not need to proxy or duplicate the binary. It can live on GitHub Pages, Vercel, or
another static host while the button redirects to GitHub Releases. That keeps the website portable
and gives downloads durable, versioned release records.

At minimum, the site should contain:

- a prominent Download button and macOS 14+ requirement;
- three-step installation instructions: open DMG, drag to Applications, launch;
- the privacy/security claims already made in the README;
- the Vercel independence/trademark disclaimer;
- links to source, license, issue tracker, and release notes;
- a short privacy policy, even for a no-collection app.

## Updates: start manual, add Sparkle deliberately

Sparkle is not required to launch. A website/release-page check is acceptable while the audience is
small. However, an app without an updater cannot retroactively update already-installed copies, so
add Sparkle 2 before the first public release if seamless automatic updates are a core expectation.

If Sparkle is added:

- Use Sparkle 2 through Swift Package Manager, generate a dedicated Ed25519 key once, embed only the
  public key as `SUPublicEDKey`, and back up the private key securely. Sparkle's `generate_appcast`
  tool generates the recommended update signatures. [Sparkle: Basic setup](https://sparkle-project.org/documentation/)
- Host `appcast.xml` over HTTPS on the static website and point its versioned enclosure URLs to
  GitHub Release ZIP assets. Sparkle supports ZIP, DMG, and tar archives; a ZIP containing the app is
  the lightweight updater payload while the DMG remains the manual-install artifact. Sparkle says
  to run `generate_appcast` over a directory of update archives and not hand-maintain the appcast.
  [Sparkle: Basic setup](https://sparkle-project.org/documentation/), [Sparkle: Publishing an update](https://sparkle-project.org/documentation/publishing/)
- Treat the Sparkle ZIP as a separate shipped deliverable. Notarize its contents, staple the app,
  then recreate the ZIP because ZIP files themselves cannot be stapled. [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- This app is sandboxed. Sparkle requires its Installer XPC service, the
  `SUEnableInstallerLauncherService` Info.plist key, and its documented temporary Mach lookup
  exception. Because this app already has outgoing network access, it does **not** need Sparkle's
  Downloader XPC service. Use Xcode Archive/Export so Sparkle's nested helpers are re-signed
  correctly. [Sparkle: Sandboxing with Sparkle](https://sparkle-project.org/documentation/sandboxing/)
- Test a genuine older notarized version updating to a genuine newer notarized version, including
  Keychain persistence and relaunch of the menu-bar app.

Do not include Sparkle in the App Store build. Apple's macOS App Review rules require App Store apps
to use the Mac App Store for updates and disallow alternate update mechanisms. [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## Release automation: second milestone

Automate after one or two manual releases have established the correct export and entitlement
outputs. The release workflow should be separate from ordinary CI and should run only on a protected
version tag or an explicit manual dispatch. A sensible sequence is:

1. Check out the exact tag and run `Scripts/verify.sh`.
2. Import the Developer ID certificate and Developer ID provisioning profile into an ephemeral
   Keychain.
3. Archive and export with the checked-in export options.
4. Inspect entitlements and the embedded profile; fail closed on unexpected values.
5. Create and sign the DMG.
6. Submit with `notarytool --wait`, inspect the log, staple, and run signature/Gatekeeper checks.
7. Generate SHA-256, optionally generate the Sparkle appcast, and upload draft release assets.
8. Publish only after a human smoke-tests the downloaded draft artifact.

GitHub documents importing a base64-encoded Apple `.p12` and macOS `.provisionprofile` from Actions
secrets into a temporary Keychain. GitHub-hosted runners are destroyed after the job, and standard
runners are free and unlimited for public repositories. [GitHub: Installing an Apple certificate on macOS runners](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications),
[GitHub: Choosing the runner for a job](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)

Keep the Developer ID private key, its password, notarization credentials or App Store Connect API
key, and Sparkle private key in encrypted secrets. Pin third-party Actions by full commit SHA, as the
current CI already does. Consider GitHub artifact attestations and immutable releases after the basic
pipeline works; GitHub describes attestations as signed provenance tying an artifact to its
repository, commit, triggering event, and build workflow. [GitHub: Securing builds](https://docs.github.com/en/code-security/tutorials/implement-supply-chain-best-practices/securing-builds)

## Is the Mac App Store appropriate?

Not as the first channel. The current app is technically close because it is already sandboxed and
has a dedicated `Release-AppStore` configuration, but the App Store adds work without solving the
main first-release problem:

- every version is subject to App Review and store metadata/privacy maintenance;
- the store must own updates, so a Sparkle path must be compiled out;
- the reviewer needs an active demo account or a fully featured demo mode for account-based
  features. The current release configurations exclude `DemoMode.swift`, so review would require a
  safe review account or a deliberate App-Store-only demo path. [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- the App Store requires privacy-practice answers and a public privacy-policy URL even if the answer
  is that the developer collects no data. [Apple: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
- the `Vercel` name and logo should be checked carefully against Vercel's trademark policy before an
  App Store submission; Apple's rules prohibit unauthorized or misleading use of protected
  third-party material. The existing independence disclaimer is helpful but is not permission.
  [Apple: App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

The App Store becomes worth revisiting if discoverability, one-click installation, App Store updates,
or TestFlight beta distribution outweigh that operational overhead. TestFlight supports macOS,
feedback, and up to 10,000 external testers, but external beta review may apply. [Apple: TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
Apps distributed through the Mac App Store do not need separate notarization because the App Store
submission process performs equivalent security checks. [Apple: Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)

Direct distribution and the App Store can coexist later. Keep the direct and App Store configuration
separation, use Developer ID + notarization + optional Sparkle for direct builds, and use Mac
Distribution/App Store Connect signing + store updates for App Store builds.

## Suggested rollout

### Milestone 1: first beta

- Wire `DEVELOPMENT_TEAM` into the Release-Direct archive path; the current unsigned CI build does
  not set it.
- Validate the explicit App ID and Developer ID profile for Keychain access.
- Archive/export manually in Xcode.
- Build, sign, notarize, staple, and test one DMG.
- Publish it as a GitHub prerelease and test the actual downloaded asset with a few users.

### Milestone 2: public direct release

- Add the stable latest-download link and a small GitHub Pages site.
- Publish the DMG, checksum, tagged source, release notes, privacy statement, and support links.
- Decide whether the first public build should already include Sparkle.

### Milestone 3: repeatability

- Add a protected release workflow using the known-good export options and signing profile.
- Add automated entitlement, notarization, architecture, and checksum assertions.
- Add Sparkle appcast generation if automatic updates are enabled.
- Enable immutable releases and optionally artifact attestations.

### Milestone 4: optional App Store channel

- Create an App Store archive scheme/configuration path that excludes Sparkle.
- Supply a review account or safe full-feature demo mode.
- Prepare store screenshots, privacy answers/policy, support URL, and trademark review.
- Use TestFlight, then submit only if the additional channel is worth maintaining.
