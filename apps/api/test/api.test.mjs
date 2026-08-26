import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApiHandler } from '../dist/server.js';
test('health endpoint is unauthenticated and run endpoint is authenticated', async () => {
  const server = createServer(createApiHandler()).listen(0, '127.0.0.1'); await new Promise((resolve) => server.once('listening', resolve));
  const port = server.address().port;
  const health = await fetch(`http://127.0.0.1:${port}/healthz`); assert.equal(health.status, 200);
  const unauth = await fetch(`http://127.0.0.1:${port}/v1/runs`, { method: 'POST' }); assert.equal(unauth.status, 401);
  server.close();
});

const runPayload = (version = 1) => ({
  skill: { id: 'schedule_from_text', version },
  client: { platform: 'ios', app_version: '0.1.0', keyboard_version: '0.1.0', locale: 'ja-JP', timezone: 'Asia/Tokyo' },
  available_input_sources: ['command', 'selection'],
  target_capabilities: ['insert_text']
});
const createRun = (port, token, key, payload = runPayload()) => fetch(`http://127.0.0.1:${port}/v1/runs`, {
  method: 'POST', headers: { authorization: `Bearer ${token}`, 'idempotency-key': key, 'content-type': 'application/json' }, body: JSON.stringify(payload)
});

test('replays the same run for an owner/key pair and rejects payload reuse', async () => {
  const server = createServer(createApiHandler()).listen(0, '127.0.0.1'); await new Promise((resolve) => server.once('listening', resolve));
  const port = server.address().port;
  const first = await createRun(port, 'alice-token', 'create-1'); const firstJson = await first.json(); assert.equal(first.status, 201);
  const replay = await createRun(port, 'alice-token', 'create-1'); const replayJson = await replay.json(); assert.equal(replay.status, 201); assert.equal(replayJson.run_id, firstJson.run_id);
  const conflict = await createRun(port, 'alice-token', 'create-1', runPayload(2)); const conflictJson = await conflict.json(); assert.equal(conflict.status, 409); assert.equal(conflictJson.error.code, 'IDEMPOTENCY_CONFLICT');
  const otherOwner = await createRun(port, 'bob-token', 'create-1'); const otherOwnerJson = await otherOwner.json(); assert.equal(otherOwner.status, 201); assert.notEqual(otherOwnerJson.run_id, firstJson.run_id);
  server.close();
});

test('rejects an oversized body while streaming it', async () => {
  const server = createServer(createApiHandler()).listen(0, '127.0.0.1'); await new Promise((resolve) => server.once('listening', resolve));
  const port = server.address().port;
  const response = await fetch(`http://127.0.0.1:${port}/v1/runs`, { method: 'POST', headers: { authorization: 'Bearer alice-token', 'idempotency-key': 'large-1' }, body: 'x'.repeat(100_001) });
  assert.equal(response.status, 413); const result = await response.json(); assert.equal(result.error.code, 'PAYLOAD_TOO_LARGE');
  server.close();
});
