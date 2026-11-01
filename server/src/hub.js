import { WebSocket } from 'ws';
import { logger } from './logger.js';
import { store } from './store.js';
import { globalRateLimiter } from './rateLimiter.js';

export class RelayHub {
  constructor() {
    // Map of deviceId -> WebSocket (Desktop Agents)
    this.agents = new Map();
    // Map of ownerId -> Set of WebSockets (Mobile Clients)
    this.mobileClients = new Map();
    // Map of requestId -> { ownerId, deviceId, timestamp, resolve, timer }
    this.pendingAccessRequests = new Map();
  }

  // Handle Desktop Agent connection
  handleAgentConnection(ws, req) {
    const url = new URL(req.url, 'http://localhost');
    const deviceIdParam = url.searchParams.get('deviceId');
    const tokenParam = url.searchParams.get('token');

    let boundDeviceId = deviceIdParam;

    logger.info({ deviceId: boundDeviceId, ip: req.socket.remoteAddress }, 'Desktop Agent connected to WebSocket');

    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        this.processAgentMessage(ws, msg, boundDeviceId, (newId) => { boundDeviceId = newId; });
      } catch (err) {
        logger.error({ err, raw: data.toString() }, 'Failed to parse message from agent');
        ws.send(JSON.stringify({ error: 'Malformed JSON payload' }));
      }
    });

    ws.on('close', () => {
      if (boundDeviceId) {
        logger.info({ deviceId: boundDeviceId }, 'Desktop Agent disconnected');
        this.agents.delete(boundDeviceId);
        store.updateOnlineStatus(boundDeviceId, false);
        this.broadcastDeviceStatusToOwners(boundDeviceId, false);
      }
    });

    ws.on('error', (err) => {
      logger.error({ err, deviceId: boundDeviceId }, 'Desktop Agent socket error');
    });
  }

  // Handle Mobile Client connection
  handleMobileConnection(ws, req) {
    const url = new URL(req.url, 'http://localhost');
    const ownerId = url.searchParams.get('ownerId');

    if (!ownerId) {
      ws.close(1008, 'Missing ownerId parameter');
      return;
    }

    logger.info({ ownerId, ip: req.socket.remoteAddress }, 'Mobile client connected to WebSocket');

    if (!this.mobileClients.has(ownerId)) {
      this.mobileClients.set(ownerId, new Set());
    }
    this.mobileClients.get(ownerId).add(ws);

    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });

    ws.on('message', (data) => {
      try {
        const msg = JSON.parse(data.toString());
        this.processMobileMessage(ws, msg, ownerId);
      } catch (err) {
        logger.error({ err, raw: data.toString() }, 'Failed to parse message from mobile');
        ws.send(JSON.stringify({ error: 'Malformed JSON payload' }));
      }
    });

    ws.on('close', () => {
      logger.info({ ownerId }, 'Mobile client disconnected');
      const set = this.mobileClients.get(ownerId);
      if (set) {
        set.delete(ws);
        if (set.size === 0) {
          this.mobileClients.delete(ownerId);
        }
      }
    });

    ws.on('error', (err) => {
      logger.error({ err, ownerId }, 'Mobile client socket error');
    });
  }

  // Process Agent messages
  processAgentMessage(ws, msg, boundDeviceId, setBoundDeviceId) {
    switch (msg.type) {
      case 'REGISTER_PENDING_DEVICE': {
        const { deviceId, deviceName, osType, publicKey, pairingSecret } = msg;
        setBoundDeviceId(deviceId);
        this.agents.set(deviceId, ws);
        store.registerPendingDevice({ deviceId, deviceName, osType, publicKey, pairingSecret });
        store.updateOnlineStatus(deviceId, true);

        ws.send(JSON.stringify({
          type: 'REGISTRATION_ACK',
          deviceId,
          status: 'PENDING_PAIRING'
        }));
        break;
      }

      case 'AGENT_AUTH': {
        const { deviceId, deviceToken } = msg;
        const device = store.getDevice(deviceId);
        if (!device || device.deviceToken !== deviceToken) {
          ws.send(JSON.stringify({ type: 'ERROR', message: 'Authentication failed: invalid device token' }));
          ws.close(4001, 'Unauthorized');
          return;
        }

        setBoundDeviceId(deviceId);
        this.agents.set(deviceId, ws);
        store.updateOnlineStatus(deviceId, true);
        this.broadcastDeviceStatusToOwners(deviceId, true);

        ws.send(JSON.stringify({
          type: 'AUTH_SUCCESS',
          deviceId,
          deviceName: device.deviceName
        }));
        break;
      }

      case 'ACCESS_RESPONSE': {
        const { requestId, deviceId, encryptedPayload, iv, authTag, agentPublicKey, error } = msg;
        const pending = this.pendingAccessRequests.get(requestId);

        if (!pending) {
          logger.warn({ requestId }, 'Received ACCESS_RESPONSE for unknown or timed out request');
          return;
        }

        clearTimeout(pending.timer);
        this.pendingAccessRequests.delete(requestId);

        if (error) {
          store.logAudit({
            ownerId: pending.ownerId,
            deviceId,
            action: 'ACCESS_GENERATION',
            status: 'FAILED',
            durationMinutes: pending.durationMinutes,
            errorDetails: error
          });

          this.sendToMobile(pending.ownerId, {
            type: 'ACCESS_FAILED',
            requestId,
            deviceId,
            error
          });
          return;
        }

        // Successfully generated
        store.logAudit({
          ownerId: pending.ownerId,
          deviceId,
          action: 'ACCESS_GENERATION',
          status: 'SUCCESS',
          durationMinutes: pending.durationMinutes
        });

        // Relay the E2E encrypted credential payload back to mobile
        // NOTICE: Server never has access to plaintext credential or agent/phone private keys!
        this.sendToMobile(pending.ownerId, {
          type: 'ACCESS_CREDENTIALS_RELAY',
          requestId,
          deviceId,
          encryptedPayload,
          iv,
          authTag,
          agentPublicKey
        });
        break;
      }

      case 'AUDIT_EVENT': {
        const { ownerId, deviceId, action, status, details } = msg;
        store.logAudit({
          ownerId: ownerId || 'unknown',
          deviceId: deviceId || boundDeviceId,
          action,
          status,
          errorDetails: details
        });
        break;
      }

      case 'PING': {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }));
        break;
      }

      default:
        logger.warn({ type: msg.type }, 'Unhandled agent message type');
    }
  }

  // Process Mobile messages
  processMobileMessage(ws, msg, ownerId) {
    switch (msg.type) {
      case 'ACCESS_REQUEST': {
        const { requestId, deviceId, durationMinutes, ephemeralPhonePublicKey } = msg;

        // Verify device ownership
        const device = store.getDevice(deviceId);
        if (!device || device.ownerId !== ownerId) {
          ws.send(JSON.stringify({
            type: 'ERROR',
            requestId,
            message: 'Device not found or not paired with this owner'
          }));
          return;
        }

        // Enforce Rate Limiting (max 3 per hour per owner)
        const rateCheck = globalRateLimiter.consume(ownerId);
        if (!rateCheck.allowed) {
          store.logAudit({
            ownerId,
            deviceId,
            action: 'ACCESS_REQUEST_REJECTED',
            status: 'RATE_LIMITED',
            errorDetails: `Rate limit exceeded. Retry in ${rateCheck.retryAfterSeconds}s`
          });

          ws.send(JSON.stringify({
            type: 'RATE_LIMIT_EXCEEDED',
            requestId,
            retryAfterSeconds: rateCheck.retryAfterSeconds,
            message: `Rate limit reached (max 3 temporary accesses per hour). Please retry in ${rateCheck.retryAfterSeconds} seconds.`
          }));
          return;
        }

        // Check if Desktop Agent is connected
        const agentWs = this.agents.get(deviceId);
        if (!agentWs || agentWs.readyState !== WebSocket.OPEN) {
          store.logAudit({
            ownerId,
            deviceId,
            action: 'ACCESS_REQUEST_FAILED',
            status: 'AGENT_OFFLINE'
          });

          ws.send(JSON.stringify({
            type: 'AGENT_OFFLINE',
            requestId,
            deviceId,
            message: 'Target laptop is offline or sleeping. Ensure laptop is powered on and awake.'
          }));
          return;
        }

        // Set up pending request tracking with timeout (15 seconds)
        const timer = setTimeout(() => {
          this.pendingAccessRequests.delete(requestId);
          store.logAudit({
            ownerId,
            deviceId,
            action: 'ACCESS_REQUEST_TIMEOUT',
            status: 'TIMEOUT'
          });
          ws.send(JSON.stringify({
            type: 'ACCESS_TIMEOUT',
            requestId,
            message: 'Laptop did not respond in time'
          }));
        }, 15000);

        this.pendingAccessRequests.set(requestId, {
          ownerId,
          deviceId,
          durationMinutes: durationMinutes || 3,
          timestamp: Date.now(),
          timer
        });

        // Forward command dispatch to Desktop Agent
        agentWs.send(JSON.stringify({
          type: 'GENERATE_ACCESS',
          requestId,
          ownerId,
          durationMinutes: Math.min(5, Math.max(1, durationMinutes || 3)),
          ephemeralPhonePublicKey
        }));
        break;
      }

      case 'GET_DEVICES': {
        const devices = store.getDevicesForOwner(ownerId);
        // Enrich with real-time socket connectivity
        const enriched = devices.map(d => ({
          ...d,
          isOnline: this.agents.has(d.deviceId) && this.agents.get(d.deviceId).readyState === WebSocket.OPEN
        }));
        ws.send(JSON.stringify({
          type: 'DEVICE_LIST',
          devices: enriched
        }));
        break;
      }

      case 'PING': {
        ws.send(JSON.stringify({ type: 'PONG', timestamp: Date.now() }));
        break;
      }

      default:
        logger.warn({ type: msg.type }, 'Unhandled mobile message type');
    }
  }

  sendToMobile(ownerId, payload) {
    const set = this.mobileClients.get(ownerId);
    if (!set) return;
    const jsonStr = JSON.stringify(payload);
    for (const ws of set) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(jsonStr);
      }
    }
  }

  broadcastDeviceStatusToOwners(deviceId, isOnline) {
    const dev = store.getDevice(deviceId);
    if (dev && dev.ownerId) {
      this.sendToMobile(dev.ownerId, {
        type: 'DEVICE_STATUS_CHANGED',
        deviceId,
        isOnline
      });
    }
  }

  startHeartbeat(intervalMs = 30000) {
    return setInterval(() => {
      for (const [deviceId, ws] of this.agents.entries()) {
        if (!ws.isAlive) {
          logger.warn({ deviceId }, 'Agent socket dead, terminating');
          this.agents.delete(deviceId);
          store.updateOnlineStatus(deviceId, false);
          this.broadcastDeviceStatusToOwners(deviceId, false);
          ws.terminate();
          continue;
        }
        ws.isAlive = false;
        ws.ping();
      }

      for (const [ownerId, set] of this.mobileClients.entries()) {
        for (const ws of set) {
          if (!ws.isAlive) {
            set.delete(ws);
            ws.terminate();
            continue;
          }
          ws.isAlive = false;
          ws.ping();
        }
      }
    }, intervalMs);
  }
}

export const hub = new RelayHub();
