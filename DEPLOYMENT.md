# AttendX — Deployment Guide

Two things ship from the same free GitHub Pages site:

| URL | What it is |
|-----|------------|
| `https://ganga2006.github.io/attendx/` | APK download page (`docs/`) |
| `https://ganga2006.github.io/attendx/admin/` | Admin console (built from `lib/main_web.dart`) |

Installed apps check Firestore at login and prompt users to update
when a newer APK is published.

## 0. Admin console on the web

The console is built and published automatically by
`.github/workflows/deploy-admin-web.yml` on every push to `main`.

**One-time setup** — on GitHub: **Settings → Pages → Build and
deployment → Source: GitHub Actions**. (This replaces the older
"Deploy from a branch → /docs" setting; the workflow republishes
`docs/` itself, so the download page stays exactly where it was.)

Then, in the Firebase console: **Authentication → Settings → Authorized
domains → Add domain → `ganga2006.github.io`**. Without this, sign-in on
the console fails with `auth/unauthorized-domain`.

After that, every push to `main` that touches `lib/`, `web/`, `docs/` or
`pubspec.yaml` rebuilds and redeploys. Watch it under the **Actions**
tab; a run takes about three minutes.

### Why the console is a separate build

`lib/main.dart` reaches TFLite, ML Kit, the camera and `dart:io` through
the face-enrollment screens — none of which compile for the web.
`lib/main_web.dart` starts from a root that only ever reaches the admin
screens (plain Flutter + Firestore), so both targets build from one
codebase without stubbing anything out.

To run it locally:

```
flutter run -d chrome -t lib/main_web.dart
```

Students and CRs are refused at the login gate — the console is for the
fixed admin account only.

## 1. One-time GitHub setup

1. Create a GitHub repository (e.g. `attendx`), then from the project folder:
   ```
   git init
   git add .
   git commit -m "AttendX v1.1.0"
   git branch -M main
   git remote add origin https://github.com/<YOUR_USERNAME>/attendx.git
   git push -u origin main
   ```
2. On GitHub: **Settings → Pages → Build and deployment**
   - Source: *Deploy from a branch*
   - Branch: `main`, folder: **/docs** → Save
3. Your download website goes live at:
   `https://<YOUR_USERNAME>.github.io/attendx/`
   (Opening it shows only the branded download page — never the app's
   dashboard or register screen.)

> Note: `.gitignore` already excludes build output; the `docs/` folder
> (website + APK) is committed on purpose. GitHub allows files up to
> 100 MB — a Flutter release APK (~40-60 MB) fits fine.

## 2. Releasing a version (every release)

1. Bump the version in TWO places (keep them equal):
   - `pubspec.yaml` → `version: 1.1.0+2`  (name + build number)
   - `lib/core/constants/app_config.dart` → `appVersionCode = 2`,
     `appVersion = '1.1.0'`
2. Build the release APK:
   ```
   flutter build apk --release
   ```
3. Copy it into the website folder as `attendx.apk`:
   ```
   copy build\app\outputs\flutter-apk\app-release.apk docs\attendx.apk
   ```
4. Commit & push:
   ```
   git add -A
   git commit -m "Release v1.1.0"
   git push
   ```
   The site + APK update within a minute or two.

## 3. Telling installed apps about the update

Create/update the Firestore document **`app_meta/android`**:

| Field               | Type    | Example                                              |
|---------------------|---------|------------------------------------------------------|
| `latestVersionCode` | number  | `3`  (must be > the code users currently have)       |
| `latestVersion`     | string  | `"1.2.0"`                                            |
| `apkUrl`            | string  | `"https://<YOUR_USERNAME>.github.io/attendx/attendx.apk"` |
| `forceUpdate`       | boolean | `false` (set `true` to block old versions entirely)  |
| `notes`             | string  | `"CR batch labs + daily digest notifications"`       |

At the next app open, the login screen shows the "Update Available"
dialog with an **Update Now** button that downloads the new APK from
your site. With `forceUpdate: true` the dialog cannot be dismissed.

Security rules: allow public **read** on `app_meta` (the check runs
before sign-in); writes admin-only.

## 4. Checklist after each release

- [ ] Website shows the new build (`Ctrl+F5` to bypass cache)
- [ ] Fresh install from the site works
- [ ] Old install shows the update dialog at login
- [ ] `forceUpdate` only set when truly breaking
