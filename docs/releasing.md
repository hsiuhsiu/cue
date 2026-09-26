# Releasing Cue

Cue's preview releases use a universal, ad hoc-signed app inside a DMG. They are
not Developer ID-signed or notarized. Packaging runs locally and adds no update
service, networking, or background work to the app.

## Prepare and verify

1. Set `CFBundleShortVersionString` and increment `CFBundleVersion` in
   `Resources/Info.plist`. Write notes in `docs/releases/v<version>.md` and update
   the README download links.
2. Run `./scripts/release.sh` with a full Xcode installation. It runs the Release
   tests and settings persistence check, builds both architectures, signs the
   complete app locally, and verifies the packaged DMG. Keep the final artifacts
   unchanged after verification.
3. Inspect `.build/releases/<version>/`. The upload assets are
   `Cue-<version>-universal.dmg` and `SHA256SUMS.txt`; build outputs and logs are
   excluded from Git. SHA-256 detects a changed download, but does not establish
   a trusted developer identity or replace notarization.
4. Test the actual downloadable artifact on another Mac where possible. Check
   the install guide, first launch, hotkey, immediate typing, app launch,
   Command+, settings, and replacement of an earlier version with settings
   preserved. Record which systems were actually tested; a deployment target
   and two compiled architectures do not establish runtime compatibility.

The script refuses to overwrite an existing version's artifact directory. To
retry a failed attempt, inspect and move aside any existing output first. Never
silently replace an already published release asset with a different build.

## Publish

Review the source changes, commit them, and push the intended branch. Create an
annotated `v<version>` tag on that commit and push it. Then create a GitHub
pre-release with the verified assets and the saved notes. For version 0.1.0:

```sh
git tag -a v0.1.0 -m "Cue 0.1.0 initial preview"
git push origin main
git push origin v0.1.0
gh release create v0.1.0 \
  .build/releases/0.1.0/Cue-0.1.0-universal.dmg \
  .build/releases/0.1.0/SHA256SUMS.txt \
  --repo hsiuhsiu/cue --verify-tag --prerelease --latest=false \
  --title "Cue 0.1.0 — Initial Preview" \
  --notes-file docs/releases/v0.1.0.md
```

Finally, download both assets from the release into a new directory and run
`shasum -a 256 -c SHA256SUMS.txt` there. Verify that the release points at the
intended commit and includes both assets. Retain the repository's visibility:
a private release is available only to people with repository access.

Installation instructions must use the system's app-specific approval flow.
Do not add commands that disable Gatekeeper or remove download quarantine.
