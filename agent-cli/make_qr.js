import QRCode from 'qrcode';
import qrcodeTerminal from 'qrcode-terminal';
import fs from 'node:fs';

const publicUrl = 'https://rhode-mathematical-less-load.trycloudflare.com';

const payload = JSON.stringify({
  deviceId: 'dev_win32_1677AA',
  relayUrl: publicUrl,
  pairingSecret: '795970',
  devicePublicKey: 'C2AwMfeyQNKQxexxw4a5SNnd1WswLW+IwA5y1obw5SM='
});

const outDir = 'C:/Users/User/.gemini/antigravity/brain/1e9fb27a-e75f-4047-a4df-a048a004f7ba';

await QRCode.toFile(outDir + '/vanishkey_qr_global.png', payload, {
  width: 400,
  margin: 2,
  color: { dark: '#0284C7', light: '#FFFFFF' }
});

console.log('---GLOBAL_QR_START---');
qrcodeTerminal.generate(payload, { small: true });
console.log('---GLOBAL_QR_END---');

const htmlContent = `<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>VanishKey Global Cloud Pairing QR</title>
  <script src="https://cdn.jsdelivr.net/npm/qrcodejs@1.0.0/qrcode.min.js"></script>
  <style>
    body { background: #0f172a; color: #f8fafc; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; box-sizing: border-box; }
    .card { background: #1e293b; border: 1px solid #334155; border-radius: 16px; padding: 32px; text-align: center; max-width: 480px; box-shadow: 0 10px 25px rgba(0,0,0,0.5); }
    .badge { display: inline-block; background: #0284c7; color: #fff; font-size: 11px; font-weight: bold; padding: 4px 10px; border-radius: 12px; margin-bottom: 12px; }
    h1 { font-size: 24px; margin-bottom: 8px; color: #38bdf8; }
    p { font-size: 14px; color: #94a3b8; margin-top: 0; line-height: 1.5; }
    #qrcode { background: white; padding: 16px; border-radius: 12px; display: inline-block; margin: 16px 0; }
    .code { font-family: monospace; background: #0f172a; padding: 12px; border-radius: 8px; font-size: 13px; color: #38bdf8; word-break: break-all; margin-top: 12px; text-align: left; line-height: 1.6; }
    .code b { color: #f8fafc; }
  </style>
</head>
<body>
  <div class="card">
    <div class="badge">🌐 Global Cloud Relay Active</div>
    <h1>VanishKey Worldwide Pairing</h1>
    <p>Scan with your phone on <b>ANY</b> Wi-Fi or <b>5G / LTE Mobile Data</b> anywhere in the world.</p>
    <div id="qrcode"></div>
    <div class="code">
      <b>Cloud Relay URL:</b> ${publicUrl}<br>
      <b>Device ID:</b> dev_win32_1677AA<br>
      <b>Pairing Secret:</b> 795970
    </div>
  </div>
  <script>
    new QRCode(document.getElementById("qrcode"), {
      text: ${JSON.stringify(payload)},
      width: 256,
      height: 256
    });
  </script>
</body>
</html>`;

fs.writeFileSync('D:/PROJECTS/VanishKey/agent-cli/pairing-qr.html', htmlContent, 'utf8');
