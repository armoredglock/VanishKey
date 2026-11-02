import { WebSocket } from 'ws';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execSync } from 'node:child_process';
import qrcodeTerminal from 'qrcode-terminal';
import QRCode from 'qrcode';
import { generateX25519KeyPair, deriveSessionKey, encryptPayload } from './cryptoHelper.js';
import { createTemporaryUser, deleteTemporaryUser } from './scriptRunner.js';

const activeCleanupTimers = new Map();

function getLanIp() {
  const nets = os.networkInterfaces();
  for (const name of Object.keys(nets)) {
    if (/wi-fi|ethernet|wlan/i.test(name)) {
      for (const net of nets[name]) {
        if (net.family === 'IPv4' && !net.internal) {
          return net.address;
        }
      }
    }
  }
  for (const name of Object.keys(nets)) {
    for (const net of nets[name]) {
      if (net.family === 'IPv4' && !net.internal && !name.toLowerCase().includes('vmware')) {
        return net.address;
      }
    }
  }
  return 'localhost';
}

const LAN_IP = getLanIp();
const CONFIG_FILE = path.join(process.cwd(), 'agent-config.json');

// Load or generate persistent identity
let identity;
if (fs.existsSync(CONFIG_FILE)) {
  try {
    identity = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  } catch (e) {
    identity = null;
  }
}

const customRelay = process.env.RELAY_URL || process.env.RELAY_HTTP_URL || identity?.relayUrl;
let RELAY_HTTP_URL = `http://${LAN_IP}:8080`;
let RELAY_WS_URL = 'ws://localhost:8080/ws/agent';

if (customRelay) {
  const cleaned = customRelay.trim().replace(/\/+$/, '');
  if (cleaned.startsWith('https://')) {
    RELAY_HTTP_URL = cleaned;
    RELAY_WS_URL = cleaned.replace('https://', 'wss://') + '/ws/agent';
  } else if (cleaned.startsWith('http://')) {
    RELAY_HTTP_URL = cleaned;
    RELAY_WS_URL = cleaned.replace('http://', 'ws://') + '/ws/agent';
  } else {
    RELAY_HTTP_URL = `https://${cleaned}`;
    RELAY_WS_URL = `wss://${cleaned}/ws/agent`;
  }
}

if (!identity) {
  const kp = generateX25519KeyPair();
  const hex = crypto.randomBytes(3).toString('hex').toUpperCase();
  identity = {
    deviceId: `dev_${process.platform}_${hex}`,
    deviceName: `${os.hostname()} (${process.platform === 'win32' ? 'Windows' : 'macOS'})`,
    osType: process.platform === 'win32' ? 'windows' : 'macos',
    publicKeyBase64: kp.publicKeyBase64,
    privateKeyBase64: kp.privateKeyBase64,
    pairingSecret: String(Math.floor(100000 + Math.random() * 900000)), // 6-digit PIN
    deviceToken: null,
    ownerId: null
  };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(identity, null, 2), 'utf8');
}

console.log('====================================================');
console.log('   VanishKey Desktop Agent (CLI Proof-of-Concept)   ');
console.log('====================================================');
console.log(`Device ID      : ${identity.deviceId}`);
console.log(`Device Name    : ${identity.deviceName}`);
console.log(`OS Platform    : ${identity.osType}`);
console.log(`Public Key     : ${identity.publicKeyBase64.substring(0, 16)}...`);
console.log(`Pairing Secret : ${identity.pairingSecret}`);
console.log(`Status         : ${identity.deviceToken ? 'PAIRED (Owner: ' + identity.ownerId + ')' : 'UNPAIRED (Awaiting Mobile Pairing)'}`);
console.log('----------------------------------------------------');

function appendAuditLog(entry) {
  const logLine = `[${new Date().toISOString()}] ${JSON.stringify(entry)}\n`;
  fs.appendFileSync('agent-audit.log', logLine, 'utf8');
}

function connect() {
  console.log(`Connecting to Relay: ${RELAY_WS_URL}`);
  const ws = new WebSocket(RELAY_WS_URL);

  ws.on('open', () => {
    console.log('[+] Connected to VanishKey Relay Server');

    // Always generate pairing-qr files so GUI & screen always have fresh valid QR
    const pairingPayload = JSON.stringify({
      deviceId: identity.deviceId,
      relayUrl: RELAY_HTTP_URL,
      pairingSecret: identity.pairingSecret,
      devicePublicKey: identity.publicKeyBase64
    });

    const htmlContent = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>VanishKey Desktop Pairing QR</title>
  <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
  <style>
    body { background: #0f172a; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 16px; padding: 32px; text-align: center; max-width: 420px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
    h1 { font-size: 24px; margin-bottom: 8px; color: #38bdf8; }
    p { font-size: 14px; color: #94a3b8; margin-top: 0; line-height: 1.5; }
    #qrcode { background: white; padding: 16px; border-radius: 12px; display: inline-block; margin: 16px 0; }
    .code { font-family: monospace; background: #0f172a; padding: 8px 12px; border-radius: 6px; font-size: 13px; color: #38bdf8; word-break: break-all; margin-top: 12px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>VanishKey Pairing QR</h1>
    <p>Scan this QR code with the VanishKey mobile app to pair your phone with this laptop.</p>
    <div id="qrcode"></div>
    <div class="code">Relay Server: ${RELAY_HTTP_URL}<br>Device ID: ${identity.deviceId}<br>Pairing Secret: ${identity.pairingSecret}</div>
  </div>
  <script>
    new QRCode(document.getElementById("qrcode"), {
      text: ${JSON.stringify(pairingPayload)},
      width: 256,
      height: 256
    });
  </script>
</body>
</html>`;
    fs.writeFileSync(path.join(process.cwd(), 'pairing-qr.html'), htmlContent, 'utf8');
    try {
      QRCode.toFile(path.join(process.cwd(), 'pairing-qr.png'), pairingPayload, { width: 320, margin: 2 }, () => {});
    } catch (e) {}

    if (identity.deviceToken) {
      // Authenticate with existing device token, sending pairingSecret to keep pairing accessible
      ws.send(JSON.stringify({
        type: 'AGENT_AUTH',
        deviceId: identity.deviceId,
        deviceToken: identity.deviceToken,
        pairingSecret: identity.pairingSecret,
        publicKey: identity.publicKeyBase64,
        deviceName: identity.deviceName,
        osType: identity.osType
      }));
    } else {
      // Register pending pairing
      ws.send(JSON.stringify({
        type: 'REGISTER_PENDING_DEVICE',
        deviceId: identity.deviceId,
        deviceName: identity.deviceName,
        osType: identity.osType,
        publicKey: identity.publicKeyBase64,
        pairingSecret: identity.pairingSecret
      }));

      console.log('\n====================================================');
      console.log('   SCAN THIS QR CODE IN THE VANISHKEY MOBILE APP    ');
      console.log('====================================================\n');
      qrcodeTerminal.generate(pairingPayload, { small: true });
      console.log('\n[Tip] You can also open "pairing-qr.html" in your web browser to scan!');
      console.log('Pairing JSON Payload:');
      console.log(pairingPayload);
      console.log('----------------------------------------------------\n');
    }
  });

  ws.on('message', async (data) => {
    try {
      const msg = JSON.parse(data.toString());

      if (msg.type === 'REGISTRATION_ACK') {
        console.log(`[i] Registered as pending pairing. Waiting for mobile app...`);
      } else if (msg.type === 'AUTH_SUCCESS') {
        console.log(`[+] Authenticated successfully as ${msg.deviceName}`);
      } else if (msg.type === 'ERROR') {
        console.error(`[-] Relay Error: ${msg.message}`);
        if (msg.message && msg.message.includes('invalid device token')) {
          console.log('[*] Resetting invalid device token and re-registering for pairing...');
          identity.deviceToken = null;
          identity.ownerId = null;
          fs.writeFileSync(CONFIG_FILE, JSON.stringify(identity, null, 2), 'utf8');
        }
      } else if (msg.type === 'DEVICE_PAIRED_EVENT') {
        console.log(`[+] Device successfully paired with Owner: ${msg.ownerId}!`);
        identity.deviceToken = msg.deviceToken;
        identity.ownerId = msg.ownerId;
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(identity, null, 2), 'utf8');
        appendAuditLog({ event: 'DEVICE_PAIRED', ownerId: msg.ownerId });
      } else if (msg.type === 'GENERATE_ACCESS') {
        const { requestId, durationMinutes, ephemeralPhonePublicKey, ownerId } = msg;
        console.log(`\n[!] Incoming Temporary Access Request:`);
        console.log(`    Request ID: ${requestId}`);
        console.log(`    Duration  : ${durationMinutes} minutes`);
        console.log(`    Owner     : ${ownerId}`);

        appendAuditLog({ event: 'ACCESS_REQUEST_RECEIVED', requestId, durationMinutes, ownerId });

        try {
          console.log(`[*] Executing unprivileged temporary user script...`);
          const creds = await createTemporaryUser(durationMinutes);
          console.log(`[+] Temporary user created: ${creds.username} (Expires at: ${creds.expires_at})`);

          // Compute Diffie-Hellman Shared Secret with Mobile's Ephemeral Public Key
          const aesKey = deriveSessionKey(identity.privateKeyBase64, ephemeralPhonePublicKey);

          // Zero-knowledge credential encryption
          const payloadToEncrypt = {
            username: creds.username,
            password: creds.password,
            created_at: creds.created_at,
            expires_at: creds.expires_at,
            duration_minutes: creds.duration_minutes,
            duration_seconds: creds.duration_seconds
          };

          const encrypted = encryptPayload(payloadToEncrypt, aesKey);

          // Return encrypted credential back to relay
          ws.send(JSON.stringify({
            type: 'ACCESS_RESPONSE',
            requestId,
            deviceId: identity.deviceId,
            encryptedPayload: encrypted.encryptedPayload,
            iv: encrypted.iv,
            authTag: encrypted.authTag,
            agentPublicKey: identity.publicKeyBase64
          }));

          console.log(`[+] End-to-end encrypted credentials sent back to Relay!`);
          appendAuditLog({ event: 'CREDENTIALS_ENCRYPTED_AND_SENT', requestId, username: creds.username });

          // Arm immediate auto-cleanup timer to log off and delete user on expiry
          const durationSec = creds.duration_seconds || (durationMinutes * 60);
          console.log(`[Timer] Auto-cleanup armed for ${creds.username} (${durationSec}s countdown)...`);

          if (activeCleanupTimers.has(creds.username)) {
            clearTimeout(activeCleanupTimers.get(creds.username));
          }

          const timerId = setTimeout(async () => {
            console.log(`\n====================================================`);
            console.log(`[!] Time expired for ${creds.username}! Instant signout & purge...`);
            console.log(`====================================================`);

            // Step 1: Instantly terminate guest session (sub-100ms)
            if (process.platform === 'win32') {
              try {
                execSync(`taskkill /F /FI "USERNAME eq ${creds.username}" /T`, { stdio: 'ignore' });
              } catch (e) {}
              try {
                execSync(`net user "${creds.username}" /delete`, { stdio: 'ignore' });
              } catch (e) {}
            }

            // Step 2: Thoroughly purge profile and directory
            try {
              const res = await deleteTemporaryUser(creds.username);
              console.log(`[+] User ${creds.username} forcefully signed out and purged:`, res);
              appendAuditLog({ event: 'ACCOUNT_PURGED_AUTO', username: creds.username, res });
            } catch (err) {
              console.error(`[-] Failed to purge ${creds.username}:`, err.message);
              appendAuditLog({ event: 'ACCOUNT_PURGE_FAILED', username: creds.username, error: err.message });
            } finally {
              activeCleanupTimers.delete(creds.username);
            }
          }, durationSec * 1000);

          activeCleanupTimers.set(creds.username, timerId);

        } catch (err) {
          console.error(`[-] Failed to generate temporary user:`, err.message);
          ws.send(JSON.stringify({
            type: 'ACCESS_RESPONSE',
            requestId,
            deviceId: identity.deviceId,
            error: err.message
          }));
          appendAuditLog({ event: 'GENERATION_FAILED', requestId, error: err.message });
        }
      } else if (msg.type === 'TERMINATE_ACTIVE_SESSION') {
        const targetUser = msg.username || 'VanishGuest';
        console.log(`\n====================================================`);
        console.log(`[!] Manual Kill-Switch Triggered: Purging ${targetUser}...`);
        console.log(`====================================================`);

        if (activeCleanupTimers.has(targetUser)) {
          clearTimeout(activeCleanupTimers.get(targetUser));
          activeCleanupTimers.delete(targetUser);
        }

        if (process.platform === 'win32') {
          try { execSync(`taskkill /F /FI "USERNAME eq ${targetUser}" /T`, { stdio: 'ignore' }); } catch (e) {}
          try { execSync(`net user "${targetUser}" /delete`, { stdio: 'ignore' }); } catch (e) {}
        }

        try {
          const res = await deleteTemporaryUser(targetUser);
          console.log(`[+] User ${targetUser} manually purged via mobile kill-switch:`, res);
          appendAuditLog({ event: 'ACCOUNT_PURGED_MANUAL', username: targetUser, res });
        } catch (err) {
          console.error(`[-] Manual purge error:`, err.message);
          appendAuditLog({ event: 'ACCOUNT_PURGE_MANUAL_FAILED', username: targetUser, error: err.message });
        }
      } else if (msg.type === 'REVOKED') {
        console.log(`[!] Device pairing was REVOKED by owner.`);
        identity.deviceToken = null;
        identity.ownerId = null;
        fs.writeFileSync(CONFIG_FILE, JSON.stringify(identity, null, 2), 'utf8');
        appendAuditLog({ event: 'DEVICE_REVOKED' });
      }
    } catch (e) {
      console.error('Error handling message:', e);
    }
  });

  ws.on('close', () => {
    console.log('[-] Disconnected from Relay Server. Reconnecting in 5s...');
    setTimeout(connect, 5000);
  });

  ws.on('error', (err) => {
    console.error('Socket error:', err.message);
  });
}

connect();
