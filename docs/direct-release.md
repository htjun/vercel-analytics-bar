# Direct macOS releases

`make release-direct` creates the distributable artifacts under `.build/ReleaseDirect/release/`:

- `Analytics-Menu-Bar-<version>.dmg`
- `Analytics-Menu-Bar-<version>.dmg.sha256`

The command builds a Developer ID app, packages it with an Applications-folder alias, signs the DMG, submits that outer artifact for notarization, retrieves the notarization log, staples the ticket, and validates the mounted app with Gatekeeper. It does not publish a GitHub Release.

## One-time Apple setup

Create and install a Developer ID Application certificate and a distribution provisioning profile that authorize the current bundle identifier and Keychain access group. Set the matching team identifier in the ignored `Config/Local.xcconfig`.

Store notarization credentials in the local Keychain. This command prompts for an app-specific password rather than placing it in shell history or this repository:

```sh
xcrun notarytool store-credentials AnalyticsMenuBarNotary \
  --apple-id "you@example.com" \
  --team-id "YOUR_TEAM_ID"
```

The default profile name is `AnalyticsMenuBarNotary`. To use another local Keychain profile, prefix the release command with `NOTARYTOOL_PROFILE=your-profile`.

## Create a release

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `Config/Base.xcconfig`, then commit the version change.
2. Run the unsigned checks:

   ```sh
   make verify
   ```

3. Create and validate the notarized artifacts:

   ```sh
   make release-direct
   ```

4. Review the two files in `.build/ReleaseDirect/release/`. The script has already verified the DMG signature, notarization ticket, disk image, and mounted app with Gatekeeper.
5. On a fresh macOS account or a second Mac, mount the final DMG, drag the app to `/Applications`, and launch it. Test an upgrade over a prior version: the Vercel credential should remain available. Then disconnect the account and confirm the credential is removed.
6. Create and push an annotated tag for the same version, for example:

   ```sh
   git tag -a v0.1.0 -m "Analytics Menu Bar 0.1.0"
   git push origin v0.1.0
   ```

7. In GitHub, create a release from that tag and upload exactly the DMG and its `.sha256` file. Publish only after the fresh-account or second-Mac smoke test passes.
