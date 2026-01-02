---
summary: "RepoBar release checklist: versioning, Sparkle appcast, signing/notarization, and verification."
read_when:
  - Preparing or validating a RepoBar release
  - Running package_app/notarize scripts or checking release assets
---

# Release checklist (RepoBar)

## ✅ Standard Release Flow (RepoBar/VibeTunnel parity)
1) **Version + changelog**
   - Update `version.env` (`MARKETING_VERSION`, `BUILD_NUMBER`).
   - Finalize the top section in `CHANGELOG.md` (no “Unreleased”; header must start with the version).

2) **Run the full release script**
   - `Scripts/release.sh`
   - Builds, signs, notarizes, generates appcast entry + HTML notes from `CHANGELOG.md`, publishes GitHub release, tags/pushes.

3) **Sparkle UX verification**
   - About → “Check for Updates…”
   - Menu only shows “Update ready, restart now?” once the update is downloaded.
   - Sparkle dialog shows formatted release notes (not escaped HTML).
   - Verify entitlements include `keychain-access-groups` for both app + CLI (login depends on shared Keychain).

## Manual steps (only when re-running pieces)
1) Debug smoke build/tests  
   - `Scripts/compile_and_run.sh`

2) Package + notarize  
   - `Scripts/package_app.sh [debug|release]`
   - Optional notarization: `NOTARIZE=1 NOTARY_PROFILE="Xcode Notary" Scripts/package_app.sh release`
   - Verify: `spctl --assess --verbose .build/release/RepoBar.app`

3) Release notes (markdown)
   - `Scripts/generate-release-notes.sh <version> > RELEASE_NOTES.md`

4) Post-publish asset check  
   - `Scripts/check-release-assets.sh <tag>` (zip + dSYM present)
