# Errorcloud

A zero-knowledge file encryption vault: a Flutter app with an iOS-style
Cupertino interface on every platform, backed by a Cloudflare Worker that only
ever stores ciphertext.

**Developed by Error**

---

## How it works

```
device                                        Cloudflare
┌──────────────────────────────┐              ┌────────────────────────────┐
│ 1. pick a file               │              │                            │
│ 2. key = Random.secure()     │              │  POST /upload              │
│    nonce = 12 random bytes   │              │   -> random 6-char id      │
│ 3. AES-256-GCM seal          │  ciphertext  │   -> Workers KV (VAULT)    │
│ 4. blob = nonce || ct || tag │ ───────────► │                            │
│ 5. link = errorcloud://      │              │  GET /download/:id         │
│    ID?key=KEY&name=NAME      │ ◄─────────── │   -> raw blob              │
└──────────────────────────────┘              └────────────────────────────┘
```

The Worker only ever holds `nonce || ciphertext || GCM tag`. It never receives
the key, the plaintext, or the file name: the name travels inside the share
link, base64url-encoded, so the server stays blind to it too.

Share link format:

```
errorcloud://X7F9A2?key=<base64url key>&name=<base64url filename>
```

`name` is optional and is only used to restore the original file name on save.

## Repository layout

```
lib/                              Flutter app (Cupertino UI)
  config.dart                     app identity + locked-down API base URL
  services/crypto_service.dart    AES-256-GCM seal/open (pointycastle)
  services/api_client.dart        Worker client + host/scheme guard
  services/file_service.dart      save decrypted bytes (SAF, then documents dir)
  models/share_link.dart          build + parse errorcloud:// links
  screens/                        home (tab scaffold), encrypt, decrypt, about
worker/                           Cloudflare Worker (blind storage) + wrangler.toml
tool/android/AndroidManifest.xml  manifest applied by CI (INTERNET, no cleartext)
tool/worker-smoke-test.mjs        local Worker test against an in-memory KV
.github/workflows/build-apk.yml   builds the release APK on push to main
```

## Backend

Live: `https://errorcloud-api.mfm965204.workers.dev`

| Method | Path            | Purpose                                    |
| ------ | --------------- | ------------------------------------------ |
| GET    | `/health`       | service banner                             |
| POST   | `/upload`       | store raw binary, returns `{id, size}`     |
| GET    | `/download/:id` | return the blob as `application/octet-stream` |

Storage is a Workers KV namespace bound to the Worker as `VAULT`
(`errorcloud-vault`, id `1e96ac39ff704617b60f80d7be977189`). R2 is **not**
enabled on this Cloudflare account, and KV caps a single value at 25 MiB, so
uploads are limited to 24 MiB in both the Worker and the app.

Redeploy with Wrangler:

```bash
cd worker
npx wrangler deploy
```

To move to R2 later, create `errorcloud-storage`, swap the `[[kv_namespaces]]`
block in `wrangler.toml` for an `[[r2_buckets]]` binding also named `VAULT`,
raise `MAX_UPLOAD_BYTES`, and change the two `env.VAULT.get(...)` calls to the
R2 object API (`get`/`head`/`put`).

Local test of the Worker logic (routing, ids, size limits, binary round-trip):

```bash
node tool/worker-smoke-test.mjs     # 10 checks
```

## App

```bash
flutter pub get
flutter run                  # or: flutter build apk --release
```

The API base URL lives in `lib/config.dart`. Point it at your own Worker if you
fork this.

## CI

`.github/workflows/build-apk.yml` runs on every push to `main`:

1. JDK 17 + Flutter stable
2. `flutter create --platforms=android` into a temp dir, then copy `android/` in,
   so no Gradle wrapper binaries are committed
3. copy `tool/android/AndroidManifest.xml` over the generated manifest
4. `flutter pub get`, then `flutter build apk --release`
5. upload `app-release.apk` as the `errorcloud-release-apk` artifact

## Security notes

* **No certificate pinning, deliberately.** Cloudflare rotates the managed
  certificate for `*.workers.dev`, so pinning its SHA-256 fingerprint would
  hard-fail the app on the first rotation. Transport hardening is instead:
  HTTPS-only, the API host locked to the configured Worker, and
  `usesCleartextTraffic="false"` in the manifest. If you later put the API on
  your own domain, pin that domain's SPKI hash with a backup pin.
* **The link is the key.** There is no recovery path: lose the link and the
  file is gone. That is the point of zero-knowledge, but it is worth stating.
* **6-character ids** give about 1.07 billion combinations, and the key is a
  separate 256-bit secret, so an id on its own is useless. Ids are still
  enumerable by anyone hammering `/download/:id`; add Cloudflare rate limiting
  before opening this to the public.
* **No delete or expiry yet.** Objects stay in KV until removed manually.
* **KV is eventually consistent.** A blob uploaded from one region can take up
  to about 60 seconds to be readable from another, so a share link opened
  immediately may briefly return 404.
* Metadata the server can still infer: blob size and upload time.
