# Errorcloud backend

A single Cloudflare Worker that stores opaque ciphertext blobs. It never sees a
key, a filename or a content type — only bytes and an ID.

## Endpoints

| Method | Path | Response |
|---|---|---|
| `POST` | `/upload` | `201 {"id":"U628AF","size":4096,"storage":"kv"}` |
| `GET` | `/download/:id` | `application/octet-stream` |
| `GET` | `/health` | `{"ok":true,"service":"errorcloud","storage":"kv"}` |

CORS is open (`Access-Control-Allow-Origin: *`), `OPTIONS` is answered with 204,
downloads are served with `Cache-Control: no-store` and
`X-Content-Type-Options: nosniff`.

## Deploy

```bash
cd backend
npx wrangler deploy
```

The live Worker is `errorcloud-api` on
`https://errorcloud-api.mfm965204.workers.dev`.

## Current deployment note

The Worker `errorcloud-api` was created from this source, but a parallel build
later redeployed it with an equivalent variant: same three routes and the same
request/response shapes, using the `errorcloud-storage` KV namespace and capping
an upload at 20 MB. The app works against it unchanged (the CI smoke test in
`build-apk.yml` uploads and re-downloads a blob against the live URL on every
build).

The source in this folder is the canonical version — it adds an R2 path, a
100 MB cap, `HEAD` support and a 30-day KV TTL. Running `npx wrangler deploy`
here replaces the live Worker with it and points it at the `vault-storage`
namespace.

## Storage

The Worker checks for an R2 binding named `VAULT_R2` first and falls back to the
KV namespace `VAULT_KV`. R2 is not enabled on the account yet — the API answers
*"Please enable R2 through the Cloudflare Dashboard"* — so KV is in use, which
limits a single object to 25 MiB. Enable R2, create the `vault-storage` bucket,
uncomment the `r2_buckets` block in `wrangler.toml` and redeploy to lift the
limit to 100 MB with no code change.

IDs are 6 characters from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (no `0/O/1/I`),
drawn from `crypto.getRandomValues` and checked for collisions before writing.
KV entries carry a 30-day TTL.
