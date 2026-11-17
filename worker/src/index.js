/**
 * Errorcloud API Worker
 *
 * Blind storage locker. The Worker never receives a key, a plaintext byte or a
 * file name: every object it stores is an AES-256-GCM sealed blob whose key
 * exists only inside the share link the client generated.
 *
 * Storage: Workers KV namespace bound as VAULT. R2 is not enabled on this
 * account, and KV caps a value at 25 MiB, so uploads are limited to 24 MiB.
 *
 * Routes
 *   GET  /             -> service banner / health check
 *   POST /upload       -> store raw binary, returns { id, size }
 *   GET  /download/:id -> return the stored blob as application/octet-stream
 */

const ID_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // 32 chars, no 0/O/1/I
const ID_LENGTH = 6;
const KEY_PREFIX = 'file:';
const MAX_UPLOAD_BYTES = 24 * 1024 * 1024; // 24 MiB, under the 25 MiB KV ceiling

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, HEAD, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...CORS_HEADERS,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
    },
  });
}

function newId() {
  const bytes = new Uint8Array(ID_LENGTH);
  crypto.getRandomValues(bytes);
  let id = '';
  for (let i = 0; i < ID_LENGTH; i += 1) {
    id += ID_ALPHABET[bytes[i] & 31];
  }
  return id;
}

export default {
  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (error) {
      return json(
        {
          error: 'Internal error',
          detail: String((error && error.message) || error),
        },
        500,
      );
    }
  },
};

async function handle(request, env) {
  const url = new URL(request.url);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (url.pathname === '/' || url.pathname === '/health') {
    return json({
      service: 'errorcloud-api',
      status: 'ok',
      app: 'Errorcloud',
      developer: 'Error',
      storage: 'kv',
      maxUploadBytes: MAX_UPLOAD_BYTES,
    });
  }

  if (url.pathname === '/upload') {
    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const declared = Number(request.headers.get('content-length') || 0);
    if (declared > MAX_UPLOAD_BYTES) {
      return json({ error: 'Payload too large' }, 413);
    }

    let body;
    try {
      body = await request.arrayBuffer();
    } catch {
      return json({ error: 'Unreadable request body' }, 400);
    }

    if (body.byteLength === 0) {
      return json({ error: 'Empty payload' }, 400);
    }
    if (body.byteLength > MAX_UPLOAD_BYTES) {
      return json({ error: 'Payload too large' }, 413);
    }

    for (let attempt = 0; attempt < 5; attempt += 1) {
      const id = newId();
      const key = KEY_PREFIX + id;

      // A miss costs nothing; a hit only happens on a 1-in-a-billion collision.
      const existing = await env.VAULT.get(key, { type: 'stream' });
      if (existing) {
        if (existing.cancel) await existing.cancel();
        continue;
      }

      await env.VAULT.put(key, body, {
        metadata: { size: body.byteLength, createdAt: new Date().toISOString() },
      });

      return json({ id, size: body.byteLength });
    }

    return json({ error: 'Could not allocate an id, please retry' }, 503);
  }

  const match = url.pathname.match(/^\/download\/([A-Za-z0-9]{6})$/);
  if (match) {
    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return json({ error: 'Method not allowed' }, 405);
    }

    const stored = await env.VAULT.get(KEY_PREFIX + match[1], {
      type: 'arrayBuffer',
    });
    if (!stored) {
      return json({ error: 'Not found' }, 404);
    }

    const headers = {
      ...CORS_HEADERS,
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': `attachment; filename="errorcloud-${match[1]}"`,
      'Cache-Control': 'no-store',
    };

    return new Response(request.method === 'HEAD' ? null : stored, {
      status: 200,
      headers,
    });
  }

  return json({ error: 'Not found' }, 404);
}
