# Errorcloud

A zero-knowledge encrypted cloud vault. Files are sealed with **AES-256-GCM on
the device**; the backend is a **blind storage locker** that only ever receives
opaque ciphertext. **SSL certificate pinning** is enforced on every request.

**Developed by Error.**

| | |
|---|---|
| App name | Errorcloud v1.0.0 |
| UI | Flutter, Cupertino (native iOS look on Android and iOS) |
| Encryption | AES-256-GCM, 256-bit key + 96-bit IV, generated per file with `Random.secure()` |
| Backend | Cloudflare Worker + R2 (KV fallback) — `https://errorcloud-api.mfm965204.workers.dev` |
| Transport | TLS with SHA-256 certificate pinning |
| CI/CD | GitHub Actions → `app-release.apk` artifact |

## How it works

1. Pick a file. The app reads the bytes and generates a fresh 256-bit key and a
   12-byte IV from `Random.secure()`.
2. The file is encrypted with AES-256-GCM. The 12-byte IV is prepended to the
   ciphertext (the GCM authentication tag is appended by the cipher).
3. Only `IV || ciphertext || tag` is uploaded. The key is **never** sent.
4. The app returns a shareable link:

   ```
   vault://<FILE_ID>?key=<BASE64URL_KEY>&n=<FILE_NAME>
   ```

   The key lives in the fragment of the link, so the link is the capability —
   anyone holding it can decrypt the file. Treat it like a password.
5. To restore, paste the link: the app fetches the blob, splits off the first
   12 bytes as the IV, and decrypts with the embedded key. GCM authentication
   fails loudly if the key is wrong or the blob was tampered with.

## Backend

Cloudflare Worker `errorcloud-api`, storage bucket `vault-storage`.

| Method | Path | Behaviour |
|---|---|---|
| `POST` | `/upload` | Raw binary body → `201 {"id":"X7F9A2","size":12345,"storage":"r2"}` |
| `GET` | `/download/:id` | `application/octet-stream`, `Cache-Control: no-store` |
| `GET` | `/health` | `{"ok":true,"service":"errorcloud","storage":"r2"}` |

File IDs are 6 characters from an unambiguous alphabet
(`ABCDEFGHJKLMNPQRSTUVWXYZ23456789`), generated with `crypto.getRandomValues`
and checked for collisions before the blob is written. CORS is open to any
origin so the app can be pointed at the Worker from a simulator or a browser.

The Worker prefers an R2 binding named `VAULT_R2` and falls back to a KV
namespace named `VAULT_KV`. **R2 is not enabled on the Cloudflare account yet**
(the API returns *"Please enable R2 through the Cloudflare Dashboard"*), so the
deployed Worker currently uses KV. KV caps a single value at 25 MiB, so uploads
above ~24 MiB are rejected with `413 payload_too_large`. Enable R2 in the
Cloudflare dashboard, create the `vault-storage` bucket, add the `VAULT_R2`
binding to the Worker and redeploy — the same code path then accepts up to
100 MB per file with no other change.

## SSL pinning

`lib/core/ssl_pinning.dart` implements two layers:

1. **`badCertificateCallback`** — a chain that does not validate (self-signed,
   unknown CA, hostname mismatch) is accepted only if the leaf certificate
   matches a pin. Everything else is rejected during the handshake.
2. **`assertEndpointPinned`** — a real handshake against `/health` whose leaf
   fingerprint must match a pin *before* any file bytes are sent. This covers
   the case `badCertificateCallback` cannot see: a MITM presenting a perfectly
   valid certificate from a public CA, where dart:io never calls the callback.

Pins are `base64(SHA-256(DER leaf certificate))`. Two sources are combined:

* `SslPinning.committedPins` — reviewed values in the repository.
* `--dart-define=SSL_PIN=<base64>` — injected by the CI build after resolving
  the live certificate, so a certificate rotation can never brick a fresh build.

To rotate a pin, run the **Fetch SSL pin** workflow, copy the printed value into
`committedPins`, and commit. Cloudflare renews `workers.dev` certificates
automatically; until the committed pin is refreshed, the build-time pin keeps
release builds working while the committed value documents intent.

With no pin configured the app refuses to connect at all (fail closed).

## Building

The Android platform folder is generated in CI so the Gradle/AGP/Kotlin
versions always match the installed Flutter SDK:

```bash
bash scripts/scaffold_android.sh   # creates android/ with label "Errorcloud"
flutter pub get
flutter build apk --release --dart-define=SSL_PIN="$(cat pin.txt)"
```

Push to `main` and GitHub Actions builds the APK:

1. Repository → **Actions** → **Build APK** → latest run.
2. The run also smoke-tests the backend: it uploads 4 KB of random bytes,
   downloads them back and compares the two.
3. Scroll to **Artifacts** → `errorcloud-release-apk` → download
   `app-release.apk`.

The APK is signed with the debug keystore, which is fine for sideloading but
must be replaced with a real keystore before publishing to the Play Store.

## Limitations

* The link carries the key. Whoever holds the link can decrypt the file; there
  is no second factor and no revocation.
* There is no delete endpoint and no expiry on the client side; KV objects are
  given a 30-day TTL server-side.
* Decrypted files are written to the app-scoped Downloads folder
  (`getDownloadsDirectory()`), so no storage permission is required. Use a share
  sheet if you want them in the public Downloads folder.
* The app icon is the default Flutter icon; add `flutter_launcher_icons` for a
  branded one.
