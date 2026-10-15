---
name: juice-bar-release
description: "Prepare a Juice Bar release with fresh native screenshots, a minimal marketing README, verified builds, and optional stable promotion."
disable-model-invocation: true
---

# Juice Bar release

Run from this repository's existing workspace. Preserve the current branch, running proxy, account switches, credentials, settings and forecast history.

## 1. Establish the release boundary

Read the user's request and inspect git status, the current diff, `scripts/build.sh` and `.github/workflows/ci.yml`. Fetch `origin/nightly` and `origin/stable`.

- **Prepare / refresh:** finish the assets, checks and reviewable branch. Leave stable unchanged.
- **Publish:** stable promotion requires the user's explicit release instruction. Creating or editing this skill is preparation, not publication.

For a new version, use the requested version, or increment the current patch version and integer bundle build in `scripts/build.sh`. `nightly` is development; installed apps follow `stable` by default. Version text is marketing metadata; updates are driven by source commits.

**Done:** scope, candidate, version and publication authorization are known.

## 2. Refresh real screenshots

```sh
python3 scripts/capture-screenshots.py
```

This builds an isolated native demo app and refreshes `assets/screenshots/{overview,account,settings}.png` plus their source-hash manifest. It uses fictional `example.com` accounts, default connection fields and separate preferences. The installed app stays running. Temporary bundles and capture logs live in `.context/release-screenshots/`.

Open **all three PNGs**. Check readable text, complete panels, correct page selection, current controls, session-relative renewal times and absence of personal details. Grey forecast colours are correct when demo evidence is insufficient. Fix layout or capture defects at their source, then recapture; preserve genuine app rendering.

If the Mac session or screen-capture permission is unavailable, report the exact capture failure and leave assets unverified. Screenshots from an older UI do not satisfy this step.

**Done:** all three freshly captured panels have been visually inspected and match this version.

## 3. Keep the README minimal

Edit `README.md` to contain only a short product pitch, real screenshots and **Install**. Keep it at **180 words or fewer**. The primary install action is the coding-agent prompt pointing at `stable/INSTALL.md`.

Sell visible benefits: pooled enabled-account capacity, individual quota/renewal visibility and confidence-gated forecasts. Match claims to the checked app. Keep developer details in `docs/development.md` and forecast mathematics in `docs/forecasting.md`.

Review the README's visual hierarchy: one logo, one clear promise, compact screenshots and one obvious install action. The screenshots should make the native product understandable without reading a feature manual.

**Done:** the README reads as marketing + installation, with correct local links and current images.

## 4. Validate and package

```sh
swift test
python3 scripts/check-release.py
bash -n scripts/build.sh scripts/install.sh scripts/uninstall.sh
git diff --check
```

Commit the checked source and asset changes first so build metadata names a clean source commit. Use the signing identity authorized for this release; preserve an existing Developer ID identity when replacing a signed app.

```sh
CODESIGN_IDENTITY="$release_signing_identity" bash scripts/build.sh
codesign --verify --deep --strict 'dist/Juice Bar.app'
```

Verify the app and zip exist, the app's `JuiceBarSourceCommit` equals the clean source commit, and `JuiceBarSourceModified` is false. Juice Bar connects directly to the proxy: its distribution contains no dashboard plugin. Refresh tracked `dist/` artifacts in a separate commit if the repository still tracks them. Check both the bundle and zip, since GitHub checkouts can lose executable bits.

Push the task branch and update its existing PR, keeping unreviewed work draft. Check CI for the exact candidate; a local build alone is not release readiness.

**Done:** source, screenshot manifest, short README, signed artifacts and candidate CI agree. Report any remaining boundary precisely.

## 5. Promote only an authorized candidate

Publish only an approved, green commit already on `origin/nightly`. If the task branch still needs merging, finish its PR preparation and report that boundary unless merging was also explicitly authorized.

Fetch again, freeze the exact candidate SHA and verify `origin/stable` is its ancestor. Fast-forward only:

```sh
git push origin "$release_candidate_sha:refs/heads/stable"
```

Read back the remote stable SHA and require an exact match. A moved ref or rejected push requires reconciliation, not a force-push. Tags are optional; moving stable is what releases this source-updating app.

Report version, published SHA and checks. Distinguish **stable published** from **installed locally** and **other Macs updated**; daily updater polling does not prove delivery. Install locally only within the user's authorized scope and verify the installed binary/signature without changing proxy state.
