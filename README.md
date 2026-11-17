# Errorcloud

A zero-knowledge file encryption vault. Flutter app (iOS-style Cupertino UI on
every platform) + Cloudflare Worker + R2 blind storage.

**Developed by Error**

---

## How it works

```
device                                   Cloudflare
┌───────────────────────────┐            ┌──────────────────────────┐
│ 1. pick file              │            │                          │
│ 2. key = Random.secure()  │            │  POST /upload            │
│    nonce = 12 random bytes│            │   -> random 6-char id    │
│ 3. AES-256-GCM seal       │  ciphertext│   -> R2 object           │
│ 4. blob = nonce||ct||tag  │ ─────────► │                          │
│ 5. link = errorcloud://   │            │  GET /download/:id       │
│    ID?key=KEY&name=NAME   │ ◄───────── │   -> raw blob            │
└───────────────────────────┘            └──────────────────────────┘
```

The Worker only ever holds `nonce || ciphertext || GCM tag`. It never receives
the key, the plaintext, or the file name — the file name travels inside the
share link, base64url-encoded, so the server stays blind to it too.

Share link format:

```
errorcloud://X7F9A2?key=<base64url key>&name=<base64url filename>
```

`name` is optional and only used to restore the original file name on save.

## Repository layout

```
lib/                     Flutter app (Cupertino UI)
  config.dart            app identity + locked-down API base URL
  services/crypto_service.dart   AES-256-GCM seal/open (pointycastle)
  services/api_client.dart       Worker client + host/scheme guard
  services/file_service.dart     save decrypted bytes (SAF / documents dir)
  models/share_link.dart         build + parse errorcloud:// links
  screens/               home (tab scaffold), encrypt, decrypt, about
worker/                  Cloudflare Worker (blind storage) + wrangler.toml
tool/android/            manifest applied by CI (INTERNET, no cleartext)
.github/workflows/       builds the release APK on push to main
```

## Backend

Live: `https://errorcloud-api.mfm965204.workers.dev`

| Method | Path            | Purpose                                   |
| ------ | --------------- | ----------------------------------------- |
| GET    | `/health`       | service banner                            |
| POST   | `/upload`       | store raw binary, returns `{id, size}`    |
| GET    | `/download/:id` | return the blob as `application/octet-stream` |

Redeploy with Wrangler:

```bash
cd worker
npx wrangler r2 bucket create errorcloud-storage   # once
npx wrangler deploy
```

The Worker needs an R2 binding named `BUCKET` pointing at `errorcloud-storage`.

## App

```bash
flutter pub get
flutter run            # or: flutter build apk --release
```

The API base URL lives in `lib/config.dart`. Point it at your own Worker if you
fork this.

## CI

`.github/workflows/build-apk.yml` runs on every push to `main`:

1. JDK 17 + Flutter stable
2. `flutter create --platforms=android` into a temp dir and copy `android/` in,
   so no Gradle wrapper binaries are committed
3. copy `tool/android/AndroidManifest.xml` over the generated manifest
4. `flutter pub get` then `flutter build apk --release`
5. upload `app-release.apk` as the `errorcloud-release-apk` artifact

## Security notes (read these)

* **No certificate pinning, deliberately.** Cloudflare rotates the managed
  certificate for `*.workers.dev`, so pinning its SHA-256 fingerprint would
  hard-fail the app on the first rotation. Instead: HTTPS-only, host locked to
  the configured Worker, `usesCleartextTraffic="false"`, and payloads encrypted
  before they leave the device. For a production app with a custom domain, pin
  the SPKI hash of *your* domain with a backup pin.
* **The link is the key.** There is no recovery path: lose the link and the
  file is gone. That is the point of zero-knowledge, but it is worth stating.
* **6-character ids** give roughly 1.07 billion combinations, and the key is a
  separate 256-bit secret, so an id alone is useless. Ids are still enumerable
  by an attacker hammering `/download/:id`; add Cloudflare rate limiting before
  opening this to the public.
* **No delete / expiry yet.** Objects live in R2 until removed manually.
* Metadata the server can still infer: blob size and upload time.
