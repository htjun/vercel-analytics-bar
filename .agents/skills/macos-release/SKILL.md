---
name: macos-release
description: Build, sign, notarize, verify, tag, and publish this repository's macOS Developer ID release. Use when the user asks to release a new version, make the app downloadable, prepare a GitHub Release, update release download links, or automate the distribution workflow.
---

# macOS Release

Run the repository's complete manual distribution workflow for the Swift macOS app. Use the existing `make release-direct` command as the source of truth for signing, DMG packaging, notarization, stapling, and Gatekeeper checks. Keep Apple credentials in Keychain and never put secrets in the repository, shell commands, release notes, or chat.

## Scope and confirmation gates

Separate these operations:

1. Prepare and verify a local release artifact.
2. Push commits or a tag to GitHub.
3. Publish a public GitHub Release.
4. Change a personal website or its hosting.

Preparation may proceed from a clear user request. Ask for explicit confirmation immediately before each external write (pushing a branch/tag, publishing a release, or editing a website). A request to create this skill is not authorization to publish a release.

Ask only for decisions that cannot be discovered safely:

- If the intended version cannot be unambiguously inferred from `Config/Base.xcconfig`, ask for the version and tag (normally `MARKETING_VERSION=0.1.0` and `v0.1.0`).
- If the working tree contains intended changes, ask whether to commit them before tagging. Preserve unrelated changes and never use `git add .`.
- If `gh auth status` fails, ask the user to authenticate with `gh auth login` or choose the browser release flow.
- If the notarytool profile is absent or invalid, ask the user to run the interactive Keychain setup. Never ask them to paste the app-specific password into chat.
- If the fresh-account/second-Mac smoke test has not happened, report that clearly and ask whether to stop, create a draft, or publish despite the skipped test. Do not claim the test passed.
- If the website repository or page path is not this repository, ask for its location before editing it. Otherwise provide the GitHub URL and leave the external site unchanged.

Do not ask for a Team ID when it is already available from `Config/Local.xcconfig` or the signing assets. Do not ask for a website host when the user only needs a download link: GitHub Releases hosts the DMG and checksum; the website only links to them.

## Resolve the repository and version

Run these read-only checks first:

```sh
git status --short
git remote get-url origin
git branch --show-current
rg -n '^(MARKETING_VERSION|CURRENT_PROJECT_VERSION)\s*=' Config/Base.xcconfig
```

Use the repository's `origin` URL to construct GitHub links. Keep the release tag, marketing version, DMG filename, and release title consistent. The current project convention is:

- tag: `v<MARKETING_VERSION>`
- title: `Analytics Menu Bar <MARKETING_VERSION>`
- DMG: `Analytics-Menu-Bar-<MARKETING_VERSION>.dmg`
- checksum: `Analytics-Menu-Bar-<MARKETING_VERSION>.dmg.sha256`

Do not tag a commit that is not the source used for the release. Before tagging, confirm that intended source/documentation changes are committed and pushed or are explicitly approved for commit/push. Leave unrelated untracked files alone.

## Prepare and verify the release

Read `docs/direct-release.md` if the workflow or naming differs from the above. Then run:

```sh
make verify
make release-direct
```

The release script requires the ignored `Config/Local.xcconfig`, a matching Developer ID Application identity, and the default Keychain profile `AnalyticsMenuBarNotary` (override with `NOTARYTOOL_PROFILE`). It creates only these publishable artifacts under `.build/ReleaseDirect/release/`:

- `Analytics-Menu-Bar-<version>.dmg`
- `Analytics-Menu-Bar-<version>.dmg.sha256`

After the command succeeds, verify the checksum from the release directory:

```sh
cd .build/ReleaseDirect/release
shasum -a 256 -c Analytics-Menu-Bar-<version>.dmg.sha256
```

The script already verifies the DMG signature, Apple notarization/stapling, disk-image integrity, mounted-app Gatekeeper assessment, universal architecture, entitlements, and absence of debug-only resources. Treat any failed check as a hard stop. Do not manually re-sign or alter the DMG afterward.

## Fresh-machine smoke test

Before recommending a public release, have the user test the exact final DMG on a fresh macOS account or a second Mac:

1. Mount the DMG and drag the app to `/Applications`.
2. Launch it and connect the Vercel account.
3. Upgrade over a prior install and confirm the credential remains available.
4. Disconnect and confirm the credential is removed.

This cannot be simulated by the release script. Record it as pending when the user has not performed it.

## Tag and publish on GitHub

Only after the user explicitly authorizes the external publish step:

```sh
git tag -a "v<version>" -m "Analytics Menu Bar <version>"
git push origin "v<version>"
```

Confirm the tag points at the intended commit. Prefer the GitHub CLI when authenticated:

```sh
gh auth status
gh release create "v<version>" \
  ".build/ReleaseDirect/release/Analytics-Menu-Bar-<version>.dmg" \
  ".build/ReleaseDirect/release/Analytics-Menu-Bar-<version>.dmg.sha256" \
  --title "Analytics Menu Bar <version>" \
  --notes "Signed and notarized macOS release. See the checksum asset for verification."
```

If `gh` is unavailable or unauthenticated, use the browser flow: open the repository's Releases page, choose **Draft a new release**, select/create the tag, upload exactly the DMG and checksum, save a draft, inspect the assets, and publish only after the user confirms. Do not upload archives, `.build` directories, provisioning profiles, certificates, or notarization logs.

## Website download links

Do not host the binary on the personal website unless the user specifically requests a second mirror. Link the website's download button to one of these GitHub URLs:

- Stable release page: `https://github.com/<owner>/<repo>/releases/latest`
- Exact release page: `https://github.com/<owner>/<repo>/releases/tag/v<version>`
- Exact direct asset: `https://github.com/<owner>/<repo>/releases/download/v<version>/Analytics-Menu-Bar-<version>.dmg`
- Latest direct asset: `https://github.com/<owner>/<repo>/releases/latest/download/Analytics-Menu-Bar-<version>.dmg`

Prefer the stable release-page URL because the current asset name includes the version and therefore changes on every release. If the user wants a direct-download button that never changes, first get approval to change the packaging convention to a stable asset filename.

If the website is in this repository, inspect its existing conventions and make the smallest link-only change. If it is hosted elsewhere, report the exact URL to paste and do not pretend the website was updated.

## Failure handling and handoff

- Apple authentication failures: stop and point to `xcrun notarytool store-credentials AnalyticsMenuBarNotary --apple-id "..." --team-id "..."`; let the user enter the app-specific password interactively.
- Signing or export failures: report the first failing check and preserve the generated diagnostics; do not bypass validation.
- GitHub authentication or permission failures: stop before retrying external writes and report the required account/repository permission.
- Never delete user source files, reset the repository, overwrite unrelated changes, or commit local signing configuration.

Report the final result with the version, source commit/tag, artifact paths, checksum result, notarization/Gatekeeper result, GitHub release URL (if published), website URL (if updated), and any remaining manual test or publication gate.
