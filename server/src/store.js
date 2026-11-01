import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { logger } from './logger.js';

export class VanishKeyStore {
  constructor(storagePath = './data/store.json') {
    this.storagePath = storagePath;
    // Map of deviceId -> pendingRegistrationData
    this.pendingRegistrations = new Map();
    // Map of deviceId -> pairedDeviceData
    this.devices = new Map();
    // Map of ownerId -> Set of deviceIds
    this.ownerDevices = new Map();
    // Array of audit records (metadata only, zero credential data)
    this.auditLogs = [];

    this._ensureDirectory();
    this._load();
  }

  _ensureDirectory() {
    const dir = path.dirname(this.storagePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
  }

  _load() {
    try {
      if (fs.existsSync(this.storagePath)) {
        const raw = fs.readFileSync(this.storagePath, 'utf8');
        const data = JSON.parse(raw);
        if (data.devices) {
          for (const [id, dev] of Object.entries(data.devices)) {
            this.devices.set(id, dev);
            if (!this.ownerDevices.has(dev.ownerId)) {
              this.ownerDevices.set(dev.ownerId, new Set());
            }
            this.ownerDevices.get(dev.ownerId).add(id);
          }
        }
        if (Array.isArray(data.auditLogs)) {
          this.auditLogs = data.auditLogs.slice(-1000); // retain last 1000
        }
        logger.info({ deviceCount: this.devices.size, logCount: this.auditLogs.length }, 'Loaded persistent store from disk');
      }
    } catch (err) {
      logger.error({ err }, 'Failed to load store from disk, starting empty');
    }
  }

  _save() {
    try {
      const data = {
        devices: Object.fromEntries(this.devices.entries()),
        auditLogs: this.auditLogs.slice(-1000)
      };
      fs.writeFileSync(this.storagePath, JSON.stringify(data, null, 2), 'utf8');
    } catch (err) {
      logger.error({ err }, 'Failed to persist store to disk');
    }
  }

  // Pending pairing registrations
  registerPendingDevice({ deviceId, deviceName, osType, publicKey, pairingSecret }) {
    const pending = {
      deviceId,
      deviceName: deviceName || 'Unknown Laptop',
      osType: osType || 'windows',
      publicKey,
      pairingSecret,
      registeredAt: Date.now(),
      expiresAt: Date.now() + 10 * 60 * 1000 // 10 min window to pair
    };
    this.pendingRegistrations.set(deviceId, pending);
    logger.info({ deviceId, deviceName }, 'Device registered as pending pairing');
    return pending;
  }

  getPendingDevice(deviceId) {
    const pending = this.pendingRegistrations.get(deviceId);
    if (!pending) return null;
    if (Date.now() > pending.expiresAt) {
      this.pendingRegistrations.delete(deviceId);
      return null;
    }
    return pending;
  }

  // Complete pairing
  pairDevice({ ownerId, deviceId, pairingSecret, phonePublicKey, customName }) {
    const pending = this.getPendingDevice(deviceId);
    if (!pending) {
      throw new Error('Device not found or pairing window expired');
    }

    if (pending.pairingSecret !== pairingSecret) {
      throw new Error('Invalid pairing secret');
    }

    const deviceToken = 'vkt_dev_' + crypto.randomBytes(24).toString('hex');
    const ownerToken = 'vkt_own_' + crypto.randomBytes(24).toString('hex');

    const pairedDevice = {
      deviceId,
      ownerId,
      deviceName: customName || pending.deviceName,
      osType: pending.osType,
      publicKey: pending.publicKey,
      phonePublicKey: phonePublicKey || null,
      deviceToken,
      ownerToken,
      pairedAt: new Date().toISOString(),
      lastSeenAt: new Date().toISOString(),
      isOnline: false
    };

    this.devices.set(deviceId, pairedDevice);
    if (!this.ownerDevices.has(ownerId)) {
      this.ownerDevices.set(ownerId, new Set());
    }
    this.ownerDevices.get(ownerId).add(deviceId);
    this.pendingRegistrations.delete(deviceId);

    this.logAudit({
      ownerId,
      deviceId,
      action: 'DEVICE_PAIRED',
      status: 'SUCCESS'
    });

    this._save();
    return pairedDevice;
  }

  getDevice(deviceId) {
    return this.devices.get(deviceId) || null;
  }

  getDevicesForOwner(ownerId) {
    const deviceIds = this.ownerDevices.get(ownerId) || new Set();
    const result = [];
    for (const id of deviceIds) {
      const dev = this.devices.get(id);
      if (dev) {
        result.push({
          deviceId: dev.deviceId,
          deviceName: dev.deviceName,
          osType: dev.osType,
          pairedAt: dev.pairedAt,
          lastSeenAt: dev.lastSeenAt,
          isOnline: dev.isOnline
        });
      }
    }
    return result;
  }

  revokeDevice(ownerId, deviceId) {
    const dev = this.devices.get(deviceId);
    if (!dev || dev.ownerId !== ownerId) {
      return false;
    }

    this.devices.delete(deviceId);
    const ownerSet = this.ownerDevices.get(ownerId);
    if (ownerSet) {
      ownerSet.delete(deviceId);
    }

    this.logAudit({
      ownerId,
      deviceId,
      action: 'DEVICE_REVOKED',
      status: 'SUCCESS'
    });

    this._save();
    return true;
  }

  updateOnlineStatus(deviceId, isOnline) {
    const dev = this.devices.get(deviceId);
    if (dev) {
      dev.isOnline = isOnline;
      dev.lastSeenAt = new Date().toISOString();
    }
  }

  // Audit Logging (Zero-Knowledge, strictly metadata only)
  logAudit({ ownerId, deviceId, action, status, durationMinutes, errorDetails }) {
    const entry = {
      id: 'log_' + crypto.randomBytes(8).toString('hex'),
      timestamp: new Date().toISOString(),
      ownerId,
      deviceId,
      action,
      status,
      durationMinutes: durationMinutes || null,
      errorDetails: errorDetails || null
    };
    this.auditLogs.push(entry);
    this._save();
    return entry;
  }

  getAuditLogs(ownerId) {
    if (!ownerId) {
      return this.auditLogs.slice(-100);
    }
    return this.auditLogs.filter(log => log.ownerId === ownerId).slice(-100);
  }
}

export const store = new VanishKeyStore();
