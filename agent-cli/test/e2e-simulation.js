import assert from 'node:assert';
import http from 'node:http';
import express from 'express';
import cors from 'cors';
import { WebSocketServer, WebSocket } from 'ws';
import crypto from 'node:crypto';
import { generateX25519KeyPair, deriveSessionKey, decryptPayload, encryptPayload } from '../src/cryptoHelper.js';
import { store } from '../../server/src/store.js';
import { hub } from '../../server/src/hub.js';
import { globalRateLimiter } from '../../server/src/rateLimiter.js';

console.log('=== STARTING VANISHKEY PHASE 2 E2E VERIFICATION SUITE ===\n');

// 1. Setup in-memory server
const app = express();
app.use(cors());
app.use(express.json());

app.get('/health', (req, res) => res.json({ status: 'healthy' }));

app.post('/api/v1/devices/pair', (req, res) => {
  try {
    const { ownerId, deviceId, pairingSecret, phonePublicKey, customName } = req.body;
    const paired = store.pairDevice({ ownerId, deviceId, pairingSecret, phonePublicKey, customName });
    res.json({ success: true, device: paired });
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

app.post('/api/v1/devices/revoke', (req, res) => {
  const { ownerId, deviceId } = req.body;
  const ok = store.revokeDevice(ownerId, deviceId);
  res.json({ success: ok });
});

const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const { pathname } = new URL(request.url, `http://${request.headers.host}`);
  if (pathname === '/ws/agent') {
    wss.handleUpgrade(request, socket, head, (ws) => hub.handleAgentConnection(ws, request));
  } else if (pathname === '/ws/mobile') {
    wss.handleUpgrade(request, socket, head, (ws) => hub.handleMobileConnection(ws, request));
  } else {
    socket.destroy();
  }
});

await new Promise((resolve) => server.listen(8999, '127.0.0.1', resolve));
console.log('[1/6] Test Relay Server listening on http://127.0.0.1:8999');

// 2. Setup Mock Desktop Agent
const agentKeys = generateX25519KeyPair();
const testDeviceId = 'dev_win_test_suite';
const testPairingSecret = '482910';
const testOwnerId = 'owner_alice_room302';

const agentWs = new WebSocket('ws://127.0.0.1:8999/ws/agent');

await new Promise((resolve) => {
  agentWs.on('open', () => {
    agentWs.send(JSON.stringify({
      type: 'REGISTER_PENDING_DEVICE',
      deviceId: testDeviceId,
      deviceName: 'Alice Windows Laptop',
      osType: 'windows',
      publicKey: agentKeys.publicKeyBase64,
      pairingSecret: testPairingSecret
    }));
  });

  agentWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'REGISTRATION_ACK') {
      console.log('[2/6] Agent connected and registered as pending pairing');
      resolve();
    }
  });
});

// 3. Mobile pairs device via HTTP API
const pairRes = await fetch('http://127.0.0.1:8999/api/v1/devices/pair', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    ownerId: testOwnerId,
    deviceId: testDeviceId,
    pairingSecret: testPairingSecret,
    phonePublicKey: 'dummy_pub_key',
    customName: 'Alice Gaming Laptop'
  })
});
const pairData = await pairRes.json();
assert.strictEqual(pairData.success, true, 'Device pairing must succeed');
console.log('[3/6] Mobile device pairing succeeded with token:', pairData.device.deviceToken.substring(0, 16) + '...');

// 4. Mobile connects to /ws/mobile
const mobileWs = new WebSocket(`ws://127.0.0.1:8999/ws/mobile?ownerId=${testOwnerId}`);
await new Promise((resolve) => mobileWs.on('open', resolve));
console.log('[4/6] Mobile connected to WebSocket hub');

// Setup Agent request handler (simulating script run + crypto)
agentWs.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.type === 'GENERATE_ACCESS') {
    const { requestId, durationMinutes, ephemeralPhonePublicKey } = msg;

    // Simulate script output
    const mockCredentials = {
      username: 'VK_Temp_88FA12',
      password: 'CSPRNG_SuperSecret_Password_999!',
      created_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + durationMinutes * 60000).toISOString(),
      duration_seconds: durationMinutes * 60
    };

    // Agent derives session key with Phone's ephemeral public key
    const sessionKey = deriveSessionKey(agentKeys.privateKeyBase64, ephemeralPhonePublicKey);
    const enc = encryptPayload(mockCredentials, sessionKey);

    agentWs.send(JSON.stringify({
      type: 'ACCESS_RESPONSE',
      requestId,
      deviceId: testDeviceId,
      encryptedPayload: enc.encryptedPayload,
      iv: enc.iv,
      authTag: enc.authTag,
      agentPublicKey: agentKeys.publicKeyBase64
    }));
  }
});

// 5. Mobile sends ACCESS_REQUEST with fresh ephemeral key
const phoneEphemeralKeys = generateX25519KeyPair();
const requestId = 'req_' + Date.now();

const responsePromise = new Promise((resolve) => {
  mobileWs.on('message', (data) => {
    const msg = JSON.parse(data.toString());
    if (msg.type === 'ACCESS_CREDENTIALS_RELAY') {
      resolve(msg);
    }
  });
});

mobileWs.send(JSON.stringify({
  type: 'ACCESS_REQUEST',
  requestId,
  ownerId: testOwnerId,
  deviceId: testDeviceId,
  durationMinutes: 3,
  ephemeralPhonePublicKey: phoneEphemeralKeys.publicKeyBase64
}));

const relayResponse = await responsePromise;
console.log('[5/6] Mobile received encrypted credentials relay from server');

// Decrypt on Mobile
const phoneSessionKey = deriveSessionKey(phoneEphemeralKeys.privateKeyBase64, relayResponse.agentPublicKey);
const decryptedCreds = decryptPayload(
  relayResponse.encryptedPayload,
  relayResponse.iv,
  relayResponse.authTag,
  phoneSessionKey
);

assert.strictEqual(decryptedCreds.username, 'VK_Temp_88FA12');
assert.strictEqual(decryptedCreds.password, 'CSPRNG_SuperSecret_Password_999!');
assert.strictEqual(decryptedCreds.duration_seconds, 180);
console.log('      Decrypted Credential Verified:');
console.log(`      Username: ${decryptedCreds.username}`);
console.log(`      Password: ${decryptedCreds.password}`);
console.log(`      Expires : ${decryptedCreds.expires_at}`);

// 6. Verify Rate Limiting (max 3 per hour)
console.log('[6/6] Verifying 3 req/hr Rate Limiter...');
// Request 1 was used above. Now consume 2 more.
globalRateLimiter.consume(testOwnerId);
globalRateLimiter.consume(testOwnerId);

// 4th request should be blocked
const fourthRateCheck = globalRateLimiter.consume(testOwnerId);
assert.strictEqual(fourthRateCheck.allowed, false, '4th request within 1 hour must be blocked');
console.log(`      Rate limiting successfully enforced: blocked with retryAfter=${fourthRateCheck.retryAfterSeconds}s`);

// Verify Zero-Knowledge audit log (audit log never contains password)
const auditLogs = store.getAuditLogs(testOwnerId);
assert(auditLogs.length > 0, 'Audit logs must be present');
const logDump = JSON.stringify(auditLogs);
assert(!logDump.includes('CSPRNG_SuperSecret_Password_999!'), 'Audit log must NEVER contain plaintext password!');
console.log('      Zero-knowledge confirmed: Plaintext credentials completely absent from server logs.');

// Cleanup
agentWs.close();
mobileWs.close();
server.close();
console.log('\n=== ALL PHASE 2 TESTS PASSED PERFECTLY ===\n');
process.exit(0);
