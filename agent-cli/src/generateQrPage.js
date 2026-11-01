import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import qrcodeTerminal from 'qrcode-terminal';
import { generateX25519KeyPair } from './cryptoHelper.js';

const CONFIG_FILE = path.join(process.cwd(), 'agent-config.json');
const HTML_FILE = path.join(process.cwd(), 'pairing-qr.html');
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
const customRelay = process.env.RELAY_URL || process.env.RELAY_HTTP_URL || identity?.relayUrl;
const RELAY_BASE_URL = customRelay ? (customRelay.startsWith('http') ? customRelay : `https://${customRelay}`) : `http://${LAN_IP}:8080`;

let identity;
if (fs.existsSync(CONFIG_FILE)) {
  try {
    identity = JSON.parse(fs.readFileSync(CONFIG_FILE, 'utf8'));
  } catch (e) {
    identity = null;
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
    pairingSecret: String(Math.floor(100000 + Math.random() * 900000)),
    deviceToken: null,
    ownerId: null
  };
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(identity, null, 2), 'utf8');
}

const pairingPayload = JSON.stringify({
  deviceId: identity.deviceId,
  relayUrl: RELAY_BASE_URL,
  pairingSecret: identity.pairingSecret,
  devicePublicKey: identity.publicKeyBase64
});

// 1. Display in terminal
console.log('\n==================================================================');
console.log('             VANISHKEY LAPTOP PAIRING QR CODE                     ');
console.log('==================================================================\n');
qrcodeTerminal.generate(pairingPayload, { small: true });

console.log('------------------------------------------------------------------');
console.log(`Device ID      : ${identity.deviceId}`);
console.log(`Device Name    : ${identity.deviceName}`);
console.log(`Pairing Secret : ${identity.pairingSecret}`);
console.log(`Relay URL      : ${RELAY_BASE_URL}`);
console.log('------------------------------------------------------------------');

// 2. Generate browser HTML page
const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VanishKey Laptop Pairing QR</title>
  <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
  <style>
    body {
      background-color: #0f172a;
      color: #f8fafc;
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      display: flex;
      flex-direction: column;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      margin: 0;
      padding: 24px;
      box-sizing: border-box;
    }
    .card {
      background-color: #1e293b;
      border: 1px solid #334155;
      border-radius: 20px;
      padding: 36px;
      text-align: center;
      max-width: 440px;
      width: 100%;
      box-shadow: 0 20px 35px -5px rgba(0, 0, 0, 0.5);
    }
    .badge {
      display: inline-block;
      background: #0369a1;
      color: #e0f2fe;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: 1px;
      text-transform: uppercase;
      padding: 4px 12px;
      border-radius: 9999px;
      margin-bottom: 12px;
    }
    h1 {
      font-size: 22px;
      margin: 0 0 8px 0;
      color: #38bdf8;
    }
    p {
      font-size: 14px;
      color: #94a3b8;
      margin: 0 0 20px 0;
      line-height: 1.5;
    }
    .qr-container {
      background: #ffffff;
      padding: 16px;
      border-radius: 16px;
      display: inline-block;
      margin: 0 auto 20px auto;
    }
    .meta-box {
      background: #0f172a;
      border: 1px solid #334155;
      border-radius: 10px;
      padding: 12px 16px;
      font-size: 13px;
      text-align: left;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
      color: #cbd5e1;
      line-height: 1.6;
    }
    .meta-box b {
      color: #38bdf8;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">Host Ready For Pairing</div>
    <h1>Scan with Mobile App</h1>
    <p>Open the VanishKey mobile app on your phone and scan this code to link your phone to this laptop.</p>
    <div class="qr-container">
      <div id="qrcode"></div>
    </div>
    <div class="meta-box">
      <div><b>Relay Server:</b> ${RELAY_BASE_URL}</div>
      <div><b>Device:</b> ${identity.deviceName}</div>
      <div><b>Device ID:</b> ${identity.deviceId}</div>
      <div><b>Pairing Secret:</b> ${identity.pairingSecret}</div>
    </div>
  </div>
  <script>
    new QRCode(document.getElementById("qrcode"), {
      text: ${JSON.stringify(pairingPayload)},
      width: 240,
      height: 240,
      correctLevel: QRCode.CorrectLevel.M
    });
  </script>
</body>
</html>`;

fs.writeFileSync(HTML_FILE, html, 'utf8');

console.log(`\n[✔] Browser QR file generated at:`);
console.log(`    file:///${HTML_FILE.replace(/\\/g, '/')}\n`);
