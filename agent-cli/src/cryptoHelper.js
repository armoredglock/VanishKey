import crypto from 'node:crypto';

const SPKI_X25519_HEADER = Buffer.from('302a300506032b656e032100', 'hex');
const PKCS8_X25519_HEADER = Buffer.from('302e020100300506032b656e04220420', 'hex');
const HKDF_INFO = Buffer.from('VanishKey_v1_SessionKey', 'utf8');

/**
 * Generate an X25519 keypair and return raw 32-byte Base64-encoded strings and KeyObjects.
 */
export function generateX25519KeyPair() {
  const kp = crypto.generateKeyPairSync('x25519', {
    publicKeyEncoding: { type: 'spki', format: 'der' },
    privateKeyEncoding: { type: 'pkcs8', format: 'der' }
  });

  const rawPublic = kp.publicKey.subarray(SPKI_X25519_HEADER.length);
  const rawPrivate = kp.privateKey.subarray(PKCS8_X25519_HEADER.length);

  return {
    publicKeyBase64: rawPublic.toString('base64'),
    privateKeyBase64: rawPrivate.toString('base64'),
    publicKeyDer: kp.publicKey,
    privateKeyDer: kp.privateKey
  };
}

/**
 * Reconstruct KeyObjects from raw 32-byte Base64 strings.
 */
export function rawPublicToKeyObject(rawBase64) {
  const rawBytes = Buffer.from(rawBase64, 'base64');
  const der = Buffer.concat([SPKI_X25519_HEADER, rawBytes]);
  return crypto.createPublicKey({ key: der, format: 'der', type: 'spki' });
}

export function rawPrivateToKeyObject(rawBase64) {
  const rawBytes = Buffer.from(rawBase64, 'base64');
  const der = Buffer.concat([PKCS8_X25519_HEADER, rawBytes]);
  return crypto.createPrivateKey({ key: der, format: 'der', type: 'pkcs8' });
}

/**
 * Derive 256-bit AES-GCM session key via X25519 DH + HKDF-SHA256
 */
export function deriveSessionKey(localPrivateKeyBase64, peerPublicKeyBase64) {
  const privKeyObj = rawPrivateToKeyObject(localPrivateKeyBase64);
  const pubKeyObj = rawPublicToKeyObject(peerPublicKeyBase64);

  const sharedSecret = crypto.diffieHellman({
    privateKey: privKeyObj,
    publicKey: pubKeyObj
  });

  return crypto.hkdfSync('sha256', sharedSecret, Buffer.alloc(0), HKDF_INFO, 32);
}

/**
 * Encrypt a JSON object using AES-256-GCM.
 * Returns Base64 strings: { encryptedPayload, iv, authTag }
 */
export function encryptPayload(plainObj, aesKey) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('aes-256-gcm', aesKey, iv);
  const jsonStr = JSON.stringify(plainObj);

  const ciphertext = Buffer.concat([
    cipher.update(jsonStr, 'utf8'),
    cipher.final()
  ]);

  const authTag = cipher.getAuthTag();

  return {
    encryptedPayload: ciphertext.toString('base64'),
    iv: iv.toString('base64'),
    authTag: authTag.toString('base64')
  };
}

/**
 * Decrypt AES-256-GCM ciphertext back into JSON object.
 */
export function decryptPayload(encryptedPayloadBase64, ivBase64, authTagBase64, aesKey) {
  const iv = Buffer.from(ivBase64, 'base64');
  const authTag = Buffer.from(authTagBase64, 'base64');
  const ciphertext = Buffer.from(encryptedPayloadBase64, 'base64');

  const decipher = crypto.createDecipheriv('aes-256-gcm', aesKey, iv);
  decipher.setAuthTag(authTag);

  const decrypted = Buffer.concat([
    decipher.update(ciphertext),
    decipher.final()
  ]);

  return JSON.parse(decrypted.toString('utf8'));
}
