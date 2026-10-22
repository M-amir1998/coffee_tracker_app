# Deployment

Nothing in this repository deploys automatically. CI builds and tests; every
step below that touches a hosted service is done by a person with access to
that service.

| Part | Where it runs | How it is deployed |
|------|---------------|--------------------|
| Database, Auth, Realtime, Storage | a Supabase project | `supabase db push` (migrations) and dashboard settings |
| Web app / PWA | static hosting (Cloudflare Pages described here) | upload of `build/web` |
| Android | Google Play or direct APK | signed App Bundle / APK |
| iOS | TestFlight / App Store | Xcode archive on a Mac |
| macOS, Windows, Linux | direct download | release builds, signed where possible |

Use **two Supabase projects**, staging and production, and deploy to staging
first. Never run `supabase/seed.sql` against a hosted project: it creates demo
users with a known password. Never run `supabase test db` against a hosted
project either: the test helpers create a `tests` schema with functions that
create users.

## 1. Supabase project

1. Create a project in the region closest to the users (for groups in Spain,
   an EU region such as Frankfurt or Paris). Keep the database password in a
   password manager; it is not needed by the app.
2. Link the repository and apply the migrations:

   ```powershell
   npx supabase@2.121.0 login
   npx supabase@2.121.0 link --project-ref <project-ref>
   npx supabase@2.121.0 db push --dry-run   # review what will be applied
   npx supabase@2.121.0 db push
   npx supabase@2.121.0 migration list      # local and remote must match
   ```

   `db push` applies `supabase/migrations` only. It does not run the seed.
3. **Authentication → URL configuration**
   - Site URL: the production web address, e.g. `https://coffee.example.org`
   - Redirect URLs: `https://coffee.example.org/**` and
     `io.github.mamir1998.coffeetracker://login-callback`
4. **Authentication → Providers → Email**: keep "Confirm email" on. Minimum
   password length 8, require letters and digits (matches the local config).
5. **Authentication → Emails**
   - Configure a custom SMTP server. The built-in sender is heavily
     rate-limited and meant for testing.
   - Paste the templates from `supabase/templates/` (confirmation, recovery,
     email change). The local `config.toml` only applies them to the local
     stack.
6. **Settings → API keys**: copy the project URL and the **publishable** key
   for the app. Do not copy the secret key anywhere near the app.
7. **Settings → Data API**: the `public` schema must stay exposed. The
   migrations revoke table privileges themselves, so new tables stay private
   either way.
8. Realtime publication and Storage buckets (`receipts`, `avatars`) are created
   by the migrations; nothing to configure.
9. Backups: check the plan's daily backups, or enable point-in-time recovery.

Avoid `supabase config push` for production unless `config.toml` has been
given production values: it would overwrite the hosted Auth settings with the
local ones (for example `site_url = http://localhost:3000`).

## 2. App configuration

Create `config/production.json` (ignored by Git) from the example:

```json
{
  "SUPABASE_URL": "https://<project-ref>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "APP_ENV": "production",
  "WEB_REDIRECT_URL": "https://coffee.example.org",
  "PUBLIC_APP_URL": "https://coffee.example.org"
}
```

- `WEB_REDIRECT_URL`: where email links return on the web (defaults to the
  current origin when empty).
- `PUBLIC_APP_URL`: used by the native apps to build invitation links. If it
  is empty, native apps share the invitation code without a link.
- A production build refuses to start with a non-https URL or a secret key.

Every build command below takes `--dart-define-from-file=config/production.json`.

## 3. Web on Cloudflare Pages

```powershell
flutter build web --release --dart-define-from-file=config/production.json
npx wrangler pages deploy build/web --project-name coffee-tracker
```

(`wrangler` asks you to log in the first time; in CI, use a
`CLOUDFLARE_API_TOKEN` secret and pin the wrangler version.)

- The app uses path URLs (`/join/ABC123`). Cloudflare Pages serves
  `index.html` for unknown paths when the build has no `404.html`, which is
  the case here. Other hosts need a rewrite of every path to `/index.html`.
- `web/_headers` adds basic security headers on Cloudflare Pages.
- Add the custom domain in the Pages project; HTTPS certificates are issued
  automatically. Then make sure the Supabase Site URL and redirect list use
  exactly that domain.
- Rollback: Cloudflare Pages keeps previous deployments; promote an older one.

The web app can be installed from supporting browsers (web app manifest). It
needs a connection to load; once loaded, coffees tapped while offline are
queued like on mobile.

## 4. Android

Requirements: Android SDK (Android Studio), Java 17.

1. Create an upload key once and keep it safe (losing it means asking Google
   for an upload key reset):

   ```powershell
   keytool -genkey -v -keystore $env:USERPROFILE\keys\coffee-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Create `android/key.properties` (ignored by Git):

   ```properties
   storeFile=C:/Users/<you>/keys/coffee-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

3. Build:

   ```powershell
   flutter build appbundle --release --dart-define-from-file=config/production.json   # Google Play
   flutter build apk --release --dart-define-from-file=config/production.json         # direct install
   ```

4. Google Play Console: create the app (`io.github.mamir1998.coffee_tracker`),
   enroll in Play App Signing, upload the `.aab` from
   `build/app/outputs/bundle/release/` to an internal testing track first.

Without `key.properties` a release build is signed with the debug key. That is
fine for testing on your own device and **must never be published**. The APK
built by CI is of that kind and uses a placeholder backend.

## 5. iOS (requires a Mac)

Requirements: macOS with Xcode (and CocoaPods if Flutter asks for it), and an
Apple Developer Program membership. iOS builds cannot be produced on Windows.

1. `flutter build ios --release --dart-define-from-file=config/production.json`
2. Open `ios/Runner.xcworkspace` in Xcode, select the Runner target, set the
   Team and keep the bundle identifier `io.github.mamir1998.coffeeTracker`
   (or change it consistently).
3. Product → Archive, then Distribute App → App Store Connect → Upload.
4. In App Store Connect, add testers in TestFlight; submit for review when
   ready.

Alternatively `flutter build ipa --release --dart-define-from-file=...` creates
the archive from the command line once signing is set up in Xcode. The CI job
`apple` (manual trigger) only proves the project compiles without signing.

## 6. macOS

`flutter build macos --release --dart-define-from-file=config/production.json`
produces `build/macos/Build/Products/Release/Coffee Tracker.app`. The app is
sandboxed with network access and user-selected file access (for exports). For
distribution outside the App Store, sign it with a Developer ID certificate and
notarize it (`xcrun notarytool submit ... --wait`, then `xcrun stapler staple`).

## 7. Windows

Requirements: Visual Studio 2022 with "Desktop development with C++", and
Windows Developer Mode (plugins need symlinks).

```powershell
flutter config --enable-windows-desktop
flutter build windows --release --dart-define-from-file=config/production.json
```

Ship the whole `build\windows\x64\runner\Release` folder (for example as a
zip). Unsigned executables trigger SmartScreen warnings; sign them with a code
signing certificate (`signtool sign /fd SHA256 /tr <timestamp-url> /td SHA256 ...`)
or package them as MSIX.

## 8. Linux

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev
flutter build linux --release --dart-define-from-file=config/production.json
```

Ship `build/linux/x64/release/bundle` (for example as a tarball). Packaging as
Flatpak or Snap is not included.

## 9. Releasing a new version

1. Update `version:` in `pubspec.yaml` (`1.0.1+2`: name + build number) and
   `appVersion` in `lib/features/settings/presentation/settings_page.dart`.
2. Add the changes to `CHANGELOG.md`.
3. Database changes are new migration files only; never edit a migration that
   was already pushed. Test with `supabase db reset` and `supabase test db`,
   push to staging, then to production **before** releasing app versions that
   depend on them.
4. Build and publish the clients. Older app versions keep working as long as
   migrations only add functions or optional parameters.

There are no down migrations: fix forward with a new migration. Financial data
is append-only, so a fix never rewrites history.

## 10. After deployment

- Sign up with a real address, confirm the email, create a group and record a
  coffee on each platform you ship.
- Open Administration → Ledger integrity → Run check in the group: all checks
  should pass.
- Watch the Supabase logs (API, Auth, Realtime) during the first days.
