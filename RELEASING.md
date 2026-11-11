# Releasing

`scripts/release.sh` (or `make release`) archives a universal Release build, signs it with
the Hardened Runtime, builds `dist/Dropshot.dmg` (app + Applications shortcut) and, when
credentials are present, notarizes and staples it.

| Environment variable | Meaning |
|---|---|
| `DEV_ID` | Signing identity, e.g. `Developer ID Application: Your Name (TEAMID)`. Unset → ad-hoc. |
| `NOTARY_PROFILE` | Name of a `notarytool` keychain profile. Unset → not notarized. |
| `SPARKLE_FEED_URL` | https URL of your `appcast.xml`. Unset → updater disabled. |
| `SPARKLE_PUBLIC_ED_KEY` | Sparkle EdDSA public key. Unset → updater disabled. |

Tools: Xcode, `brew install xcodegen create-dmg`.

## Ad-hoc build (no Apple account)

```bash
scripts/release.sh
```

Runs on the Mac that built it. Other Macs will refuse to open it.

## Notarized build

One-time setup:

1. Join the Apple Developer Program and create a **Developer ID Application** certificate
   (Xcode → Settings → Accounts → Manage Certificates). Confirm it is installed:

   ```bash
   security find-identity -v -p codesigning
   ```

2. Create an app-specific password at appleid.apple.com, then store notary credentials in the
   Keychain (you will be prompted for the password):

   ```bash
   xcrun notarytool store-credentials dropshot-notary --apple-id you@example.com --team-id TEAMID
   ```

Each release:

```bash
DEV_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=dropshot-notary scripts/release.sh
```

The script signs inside-out (Sparkle's XPC services, `Autoupdate`, `Updater.app`, the
framework, then the app) with `--options runtime --timestamp`, signs the DMG, submits it with
`xcrun notarytool submit --wait`, staples it and checks it with `spctl`.

## Sparkle updates

Sparkle's tools are downloaded with the package, into
`build/SourcePackages/artifacts/sparkle/Sparkle/bin/` (run `make build` once first).

1. Generate the EdDSA key pair, once. The private key goes into your login Keychain; the
   command prints the public key.

   ```bash
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys
   ```

   Back up the private key somewhere safe (`generate_keys -x private-key-file` exports it;
   never commit that file — `.gitignore` already excludes `sparkle_private_key*`).

2. Decide where the feed lives, e.g. `https://example.com/dropshot/appcast.xml`.

3. Build with both values. This is what switches the updater on:

   ```bash
   SPARKLE_FEED_URL="https://example.com/dropshot/appcast.xml" SPARKLE_PUBLIC_ED_KEY="<public key>" DEV_ID="…" NOTARY_PROFILE=dropshot-notary scripts/release.sh
   ```

4. Put the notarized DMG in a folder with a versioned name and generate the appcast. It signs
   each archive with the key from your Keychain.

   ```bash
   mkdir -p updates && cp dist/Dropshot.dmg updates/Dropshot-0.1.0.dmg
   ```

   ```bash
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast --download-url-prefix https://example.com/dropshot/ updates
   ```

   To sign a single file by hand instead (prints `sparkle:edSignature` and `length`):

   ```bash
   build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update updates/Dropshot-0.1.0.dmg
   ```

5. Upload the DMG and `updates/appcast.xml` to the feed location. `appcast.xml` in the
   repository root is a template showing the expected shape.

## Version numbers

Set `MARKETING_VERSION` (shown to users) and `CURRENT_PROJECT_VERSION` (must increase with
every release; Sparkle compares it) in `project.yml`.

## Checklist

- [ ] Version numbers bumped in `project.yml`
- [ ] `make test` passes; `scripts/smoke-test.sh` passes
- [ ] Manual checklist in TESTING.md walked through on a notched Mac
- [ ] `scripts/release.sh` with `DEV_ID` and `NOTARY_PROFILE` ends with "signed, notarized and stapled"
- [ ] DMG opens on a second Mac without a Gatekeeper warning
- [ ] Appcast updated and uploaded; "Check for Updates…" in the previous version finds it

## Icon

`make icon` redraws `Dropshot/Resources/AppIcon.icns` from `scripts/make-icon.swift`. It is a
placeholder; replace the `.icns` with final artwork when you have it.
