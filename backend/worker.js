/**
 * Errorcloud — blind storage backend
 * ---------------------------------------------------------------
 * Zero-knowledge file locker. The Worker only ever sees opaque
 * ciphertext blobs; keys never leave the device.
 *
 *   POST /upload          raw binary body  -> { id, size }
 *   GET  /download/:id    application/octet-stream
 *   GET  /health          service probe
 *
 * Storage: R2 binding `VAULT_R2` if present, otherwise KV `VAULT_KV`.
 */

const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
const ID_LEN = 6;
const MAX_BYTES = 100 * 1024 * 1024;
const KV_MAX_BYTES = 24 * 1024 * 1024; // KV hard limit is 25 MiB
const TTL_SECONDS = 60 * 60 * 24 * 30; // KV objects expire after 30 days

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Accept',
  'Access-Control-Max-Age': '86400',
  'Access-Control-Expose-Headers': 'X-Vault-Engine, Content-Length',
};

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...CORS, ...extra },
  });
}

function newId() {
  const bytes = new Uint8Array(ID_LEN);
  crypto.getRandomValues(bytes);
  let out = '';
  for (let i = 0; i < ID_LEN; i++) out += ALPHABET[bytes[i] % ALPHABET.length];
  return out;
}

function validId(id) {
  return typeof id === 'string' && /^[A-Z2-9]{6}$/.test(id);
}

function engine(env) {
  if (env.VAULT_R2) return 'r2';
  if (env.VAULT_KV) return 'kv';
  return null;
}

async function exists(env, id) {
  if (env.VAULT_R2) return (await env.VAULT_R2.head(id)) !== null;
  return (await env.VAULT_KV.getWithMetadata(id, { type: 'arrayBuffer' })) !== null &&
    (await env.VAULT_KV.get(id, { type: 'stream' })) !== null;
}

async function put(env, id, bytes) {
  if (env.VAULT_R2) {
    await env.VAULT_R2.put(id, bytes, {
      httpMetadata: { contentType: 'application/octet-stream' },
      customMetadata: { created: new Date().toISOString() },
    });
    return;
  }
  await env.VAULT_KV.put(id, bytes, {
    expirationTtl: TTL_SECONDS,
    metadata: { created: new Date().toISOString(), size: bytes.byteLength },
  });
}

async function get(env, id) {
  if (env.VAULT_R2) {
    const obj = await env.VAULT_R2.get(id);
    if (!obj) return null;
    return { body: obj.body, size: obj.size };
  }
  const buf = await env.VAULT_KV.get(id, { type: 'arrayBuffer' });
  if (!buf) return null;
  return { body: buf, size: buf.byteLength };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, '') || '/';

    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    const store = engine(env);

    // ---- health -------------------------------------------------------
    if (path === '/health' || path === '/') {
      return json({ ok: true, service: 'errorcloud', storage: store, time: new Date().toISOString() });
    }

    // ---- upload -------------------------------------------------------
    if ((path === '/upload' || path === '/api/upload') && request.method === 'POST') {
      if (!store) return json({ error: 'storage_not_configured' }, 500);

      const declared = Number(request.headers.get('content-length') || 0);
      const cap = store === 'kv' ? KV_MAX_BYTES : MAX_BYTES;
      if (declared > cap) return json({ error: 'payload_too_large', limit: cap }, 413);

      let bytes;
      try {
        bytes = new Uint8Array(await request.arrayBuffer());
      } catch {
        return json({ error: 'unreadable_body' }, 400);
      }
      if (bytes.byteLength === 0) return json({ error: 'empty_body' }, 400);
      if (bytes.byteLength > cap) return json({ error: 'payload_too_large', limit: cap }, 413);

      let id = null;
      for (let attempt = 0; attempt < 6; attempt++) {
        const candidate = newId();
        if (!(await exists(env, candidate))) { id = candidate; break; }
      }
      if (!id) return json({ error: 'id_collision' }, 503);

      await put(env, id, bytes);
      return json({ id, size: bytes.byteLength, storage: store }, 201, { 'X-Vault-Engine': store });
    }

    // ---- download -----------------------------------------------------
    if (path.startsWith('/download/') || path.startsWith('/api/download/')) {
      if (request.method !== 'GET' && request.method !== 'HEAD') {
        return json({ error: 'method_not_allowed' }, 405);
      }
      if (!store) return json({ error: 'storage_not_configured' }, 500);

      const id = decodeURIComponent(path.split('/').pop() || '').toUpperCase();
      if (!validId(id)) return json({ error: 'invalid_id' }, 400);

      const found = await get(env, id);
      if (!found) return json({ error: 'not_found' }, 404);

      const headers = {
        'Content-Type': 'application/octet-stream',
        'Content-Length': String(found.size),
        'Cache-Control': 'no-store',
        'X-Content-Type-Options': 'nosniff',
        'X-Vault-Engine': store,
        ...CORS,
      };
      return new Response(request.method === 'HEAD' ? null : found.body, { status: 200, headers });
    }

    return json({ error: 'not_found', hint: 'POST /upload, GET /download/:id' }, 404);
  },
};
