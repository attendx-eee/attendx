# AttendX — Deployment Guide

Three things ship from the same free GitHub Pages site:

| URL | What it is |
|-----|------------|
| `https://attendx-eee.github.io/attendx/` | Download page (`docs/`) — detects iOS vs Android |
| `https://attendx-eee.github.io/attendx/admin/` | Staff console (`lib/main_web.dart`) |
| `https://attendx-eee.github.io/attendx/app/` | Student web app (`lib/main_student_web.dart`) |

### Why there are three entry points

`lib/main.dart` reaches the camera, TFLite, ML Kit and `dart:io`
through face enrollment and registration. None of that compiles for the
web, and a runtime flag doesn't help — the compiler follows the import
regardless. So each target gets a root that only reaches what it can
actually build.

The student web app is **view-only by design**: attendance, timetable,
notifications, read-only profile. It cannot enroll a face, because a
browser has no on-device model. iPhone students register once at the
office on a department Android device; after that they use the web app.
There is no iOS build because publishing one needs a paid Apple
developer account.

Installed apps check Firestore at login and prompt users to update
when a newer APK is published.


## Push notifications (free, no card)

Realtime alerts — "you were marked absent", a cancelled class — need a
real push, because the app's Firestore listener stops the moment the app
is killed.

FCM itself is free and unlimited on the Spark plan. What is *not* free
is Cloud Functions, which needs the Blaze plan and a card on file. But
Blaze was only ever buying somewhere to run the sender, and the sender
is 300 lines that can run anywhere. It runs on Cloudflare Workers'
free tier instead: no card, always on, 100,000 requests a day against a
workload that uses about 1,440.

`functions/index.js` is the Cloud Functions version of the same thing.
It is kept for the day this project has a budget; it is not deployed.

### How it works

Everything in the app already writes to the `notifications` collection
when it wants to tell someone something. Each document now carries
`pushed: false`. A Cloudflare cron sweeps once a minute for those,
looks up the recipient's `fcmTokens`, sends, and flips the flag.

A cron sweep rather than a webhook, deliberately. A webhook is faster
but needs a public endpoint, which needs authentication, which means a
shared secret inside the APK where anyone can extract it. The sweep has
no attack surface, and it still delivers when the device that wrote the
notification goes offline a second later. The cost is up to 60 seconds
of delay, which for an attendance alert is not a meaningful difference.

### One-time setup

1. **Service account key** — Firebase Console → ⚙ Project settings →
   Service accounts → **Generate new private key**. This does not need
   Blaze. Keep the JSON off GitHub.

2. **Cloudflare account** — sign up at dash.cloudflare.com. Free, no
   card. Then:

   ```
   cd worker
   npm install
   npx wrangler login
   ```

3. **Secrets**, pasted from the JSON:

   ```
   npx wrangler secret put FIREBASE_PROJECT_ID     # attendx-18717
   npx wrangler secret put FIREBASE_CLIENT_EMAIL   # client_email
   npx wrangler secret put FIREBASE_PRIVATE_KEY    # private_key, whole PEM
   ```

   Paste the private key exactly as it appears in the JSON, including
   the `-----BEGIN PRIVATE KEY-----` line. The worker converts the
   escaped newlines back itself.

4. **Deploy**:

   ```
   npx wrangler deploy
   ```

5. **Check it** — open the worker URL printed by deploy. It runs one
   sweep and replies with what it did, e.g. `OK — sent 2, skipped 0,
   scanned 2`. `npx wrangler tail` streams the cron logs live.

Live at: `https://attendx-push.attendx-eee.workers.dev`

### If pushes stop arriving

- `npx wrangler tail` — the sweep logs every run and every failure.
- Check the student's account document has a non-empty `fcmTokens`
  array. Empty means the app never registered, so there is nothing to
  send to.
- Check `notifications` for documents stuck at `pushed: false`. Stuck
  means the worker isn't running; missing the field entirely means an
  old document from before this was added, and those are ignored by
  design.

## 0. Web apps

Both web front-ends are built and published automatically by
`.github/workflows/deploy-admin-web.yml` on every push to `main` that
touches `lib/`, `web/`, `docs/` or `pubspec.yaml`.

**One-time setup** — on GitHub: **Settings → Pages → Build and
deployment → Source: GitHub Actions**. (This replaces the older
"Deploy from a branch → /docs" setting; the workflow republishes
`docs/` itself, so the download page stays exactly where it was.)

Then, in the Firebase console: **Authentication → Settings → Authorized
domains → Add domain → `attendx-eee.github.io`**. Without this, sign-in on
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
> (website + APK) is committed on purpose. GitHub rejects any file over
> **100 MB**, and rejects it at push time — by which point the file is
> already in your commit history, so deleting it and committing again
> doesn't help. See the build step below for why this matters.

## 2. Releasing a version (every release)

1. Bump the version in TWO places (keep them equal):
   - `pubspec.yaml` → `version: 1.1.0+2`  (name + build number)
   - `lib/core/constants/app_config.dart` → `appVersionCode = 2`,
     `appVersion = '1.1.0'`
2. Build the release APK — **always with `--split-per-abi`**:
   ```
   flutter build apk --release --split-per-abi
   ```
   Plain `flutter build apk` produces a *fat* APK containing native code
   for all three CPU architectures at once. That's ~120 MB, which
   GitHub refuses to accept, and ~3x larger than any phone needs — a
   device only ever runs one of the three. Splitting gives a ~45 MB APK
   per architecture.

3. Copy the arm64 build into the website folder. Every Android phone
   from roughly 2016 onward is arm64; the armeabi-v7a and x86_64 builds
   are only worth publishing if you actually have old or emulated
   devices to support:
   ```
   copy build\app\outputs\flutter-apk\app-arm64-v8a-release.apk docs\attendx-v1.2.6.apk
   ```
   Check the size before committing. If it's over ~60 MB, you built a
   fat APK by mistake — rebuild with the flag.

   > **If a push is already rejected for size:** the file is in your
   > history, so it has to come out of the commit, not just the folder.
   > `git reset --soft HEAD~1`, then
   > `git restore --staged docs/<file>.apk`, delete it, rebuild
   > correctly, and commit again.
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
| `latestVersionCode` | number  | `9`  (must be > the code users currently have)       |
| `latestVersion`     | string  | `"1.2.6"`                                            |
| `apkUrl`            | string  | `"https://attendx-eee.github.io/attendx/attendx-v1.2.6.apk"` |
| `forceUpdate`       | boolean | `false` (set `true` to block old versions entirely)  |
| `notes`             | string  | `"CR batch labs + daily digest notifications"`       |

At the next app open, the login screen shows the "Update Available"
dialog with an **Update Now** button that downloads the new APK from
your site. With `forceUpdate: true` the dialog cannot be dismissed.

> **`apkUrl` must include the version in the filename.** The APKs in
> `docs/` are named `attendx-v1.2.6.apk`, not `attendx.apk` — the app
> opens this string verbatim, so a filename that doesn't exist gives
> everyone a 404 on the Update button.
>
> Before saving, paste the URL into a browser. If it downloads, the
> button works; if you get a 404, fix it here rather than in the app.
>
> Update `apkUrl` **after** the push has finished and GitHub Pages has
> rebuilt (a minute or two). Bumping `latestVersionCode` first points
> every installed app at a file that isn't live yet.

Security rules: allow public **read** on `app_meta` (the check runs
before sign-in); writes admin-only.

## 4. Checklist after each release

- [ ] Website shows the new build (`Ctrl+F5` to bypass cache)
- [ ] Fresh install from the site works
- [ ] Old install shows the update dialog at login
- [ ] `forceUpdate` only set when truly breaking
