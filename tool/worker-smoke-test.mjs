/**
 * Local smoke test for the Errorcloud Worker.
 *
 * Runs the real module against an in-memory KV stand-in, so routing, id
 * generation, size limits and binary round-tripping are exercised without
 * touching Cloudflare.
 *
 *   node tool/worker-smoke-test.mjs
 */

import assert from 'node:assert/strict';
import worker from '../worker/src/index.js';

function makeKv() {
  const store = new Map();
  return {
    store,
    async put(key, value, options) {
      const bytes = value instanceof ArrayBuffer ? new Uint8Array(value) : value;
      store.set(key, { bytes, options });
    },
    async get(key, options) {
      const entry = store.get(key);
      if (!entry) return null;
      const type = options && options.type;
      if (type === 'stream') {
        return new Blob([entry.bytes]).stream();
      }
      if (type === 'arrayBuffer') {
        return entry.bytes.buffer.slice(
          entry.bytes.byteOffset,
          entry.bytes.byteOffset + entry.bytes.byteLength,
        );
      }
      return new TextDecoder().decode(entry.bytes);
    },
  };
}

const BASE = 'https://errorcloud.test';
const env = { VAULT: makeKv() };
const results = [];

async function check(name, fn) {
  await fn();
  results.push(name);
  console.log(`ok  ${name}`);
}

await check('health', async () => {
  const res = await worker.fetch(new Request(`${BASE}/health`), env);
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.equal(body.status, 'ok');
  assert.equal(body.developer, 'Error');
});

await check('CORS preflight', async () => {
  const res = await worker.fetch(
    new Request(`${BASE}/upload`, { method: 'OPTIONS' }),
    env,
  );
  assert.equal(res.status, 204);
  assert.equal(res.headers.get('Access-Control-Allow-Origin'), '*');
});

await check('upload rejects empty payload', async () => {
  const res = await worker.fetch(
    new Request(`${BASE}/upload`, { method: 'POST', body: new Uint8Array(0) }),
    env,
  );
  assert.equal(res.status, 400);
});

await check('upload rejects GET', async () => {
  const res = await worker.fetch(new Request(`${BASE}/upload`), env);
  assert.equal(res.status, 405);
});

const payload = new Uint8Array(4096).map((_, i) => (i * 37) % 256);
let fileId = '';

await check('upload stores blob and returns 6-char id', async () => {
  const res = await worker.fetch(
    new Request(`${BASE}/upload`, { method: 'POST', body: payload }),
    env,
  );
  assert.equal(res.status, 200);
  const body = await res.json();
  assert.match(body.id, /^[A-Z0-9]{6}$/);
  assert.equal(body.size, payload.length);
  fileId = body.id;
  assert.equal(env.VAULT.store.size, 1);
});

await check('download returns identical bytes', async () => {
  const res = await worker.fetch(new Request(`${BASE}/download/${fileId}`), env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('Content-Type'), 'application/octet-stream');
  const bytes = new Uint8Array(await res.arrayBuffer());
  assert.deepEqual(bytes, payload);
});

await check('download of unknown id is 404', async () => {
  const res = await worker.fetch(new Request(`${BASE}/download/ZZZZZZ`), env);
  assert.equal(res.status, 404);
});

await check('download rejects malformed id', async () => {
  const res = await worker.fetch(new Request(`${BASE}/download/toolong`), env);
  assert.equal(res.status, 404);
});

await check('HEAD download returns no body', async () => {
  const res = await worker.fetch(
    new Request(`${BASE}/download/${fileId}`, { method: 'HEAD' }),
    env,
  );
  assert.equal(res.status, 200);
  assert.equal((await res.arrayBuffer()).byteLength, 0);
});

await check('oversized upload is rejected', async () => {
  const res = await worker.fetch(
    new Request(`${BASE}/upload`, {
      method: 'POST',
      headers: { 'content-length': String(25 * 1024 * 1024) },
      body: new Uint8Array(16),
    }),
    env,
  );
  assert.equal(res.status, 413);
});

console.log(`\n${results.length} checks passed`);
