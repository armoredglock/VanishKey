import http from 'node:http';
import express from 'express';
import cors from 'cors';
import { WebSocketServer } from 'ws';
import { logger } from './logger.js';
import { store } from './store.js';
import { hub } from './hub.js';

const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0';

const app = express();
app.use(cors());
app.use(express.json());

// Request logging middleware
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    logger.info({
      method: req.method,
      url: req.url,
      status: res.statusCode,
      durationMs: Date.now() - start
    }, 'HTTP Request');
  });
  next();
});

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// Device Pairing Endpoint (Called by Mobile App after scanning QR)
app.post('/api/v1/devices/pair', (req, res) => {
  try {
    const { ownerId, deviceId, pairingSecret, phonePublicKey, customName } = req.body;
    if (!ownerId || !deviceId || !pairingSecret) {
      return res.status(400).json({ error: 'ownerId, deviceId, and pairingSecret are required' });
    }

    const paired = store.pairDevice({
      ownerId,
      deviceId,
      pairingSecret,
      phonePublicKey,
      customName
    });

    // Notify the agent socket if connected
    const agentWs = hub.agents.get(deviceId);
    if (agentWs) {
      agentWs.send(JSON.stringify({
        type: 'DEVICE_PAIRED_EVENT',
        deviceId,
        deviceToken: paired.deviceToken,
        ownerId
      }));
    }

    res.json({
      success: true,
      device: {
        deviceId: paired.deviceId,
        deviceName: paired.deviceName,
        osType: paired.osType,
        deviceToken: paired.deviceToken,
        ownerToken: paired.ownerToken
      }
    });
  } catch (err) {
    logger.error({ err }, 'Error during device pairing');
    res.status(400).json({ error: err.message });
  }
});

// List paired devices for an owner
app.get('/api/v1/devices/list', (req, res) => {
  const { ownerId } = req.query;
  if (!ownerId) {
    return res.status(400).json({ error: 'ownerId query parameter is required' });
  }

  const devices = store.getDevicesForOwner(ownerId);
  const enriched = devices.map(d => ({
    ...d,
    isOnline: hub.agents.has(d.deviceId) && hub.agents.get(d.deviceId).readyState === 1
  }));

  res.json({ devices: enriched });
});

// Revoke a paired device
app.post('/api/v1/devices/revoke', (req, res) => {
  const { ownerId, deviceId } = req.body;
  if (!ownerId || !deviceId) {
    return res.status(400).json({ error: 'ownerId and deviceId are required' });
  }

  const ok = store.revokeDevice(ownerId, deviceId);
  if (!ok) {
    return res.status(404).json({ error: 'Device not found or not owned by caller' });
  }

  // Disconnect agent socket if open
  const agentWs = hub.agents.get(deviceId);
  if (agentWs) {
    agentWs.send(JSON.stringify({ type: 'REVOKED', message: 'This device pairing was revoked by owner' }));
    agentWs.close(4003, 'Device Revoked');
    hub.agents.delete(deviceId);
  }

  res.json({ success: true, revokedDeviceId: deviceId });
});

// Audit trail endpoint (Zero-Knowledge, metadata only)
app.get('/api/v1/audit/logs', (req, res) => {
  const { ownerId } = req.query;
  const logs = store.getAuditLogs(ownerId);
  res.json({ logs });
});

// Create HTTP and WebSocket server
const server = http.createServer(app);
const wss = new WebSocketServer({ noServer: true });

server.on('upgrade', (request, socket, head) => {
  const { pathname } = new URL(request.url, `http://${request.headers.host}`);

  if (pathname === '/ws/agent') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      hub.handleAgentConnection(ws, request);
    });
  } else if (pathname === '/ws/mobile') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      hub.handleMobileConnection(ws, request);
    });
  } else {
    socket.destroy();
  }
});

// Start heartbeat timer
const heartbeatTimer = hub.startHeartbeat(25000);

server.listen(PORT, HOST, () => {
  logger.info({ port: PORT, host: HOST }, `VanishKey Relay Server listening on http://${HOST}:${PORT}`);
});

// Graceful shutdown
const shutdown = () => {
  logger.info('Shutting down server gracefully...');
  clearInterval(heartbeatTimer);
  server.close(() => {
    logger.info('HTTP and WebSocket server closed.');
    process.exit(0);
  });
};

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
