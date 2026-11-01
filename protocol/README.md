# VanishKey End-to-End Cryptographic Protocol

VanishKey provides zero-knowledge credential generation: **The relay server never sees or stores generated credentials in plaintext.** All credential exchange is protected by an authenticated Diffie-Hellman key exchange (X25519) combined with AES-256-GCM authenticated encryption.

## 1. Cryptographic Primitives

| Component | Primitive | Specification |
| :--- | :--- | :--- |
| **Asymmetric Key Exchange** | Curve25519 (X25519) | RFC 7748, 32-byte public/private keys |
| **Key Derivation Function** | HKDF-SHA256 | RFC 5869, info = `"VanishKey_v1_SessionKey"` |
| **Symmetric Cipher** | AES-256-GCM | NIST SP 800-38D, 12-byte IV, 16-byte Auth Tag |
| **Transport Layer** | TLS 1.3 / WSS | Authenticated, transport-level confidentiality |
| **Ephemeral Passwords** | CSPRNG | 24-char high-entropy string (96+ bits of entropy) |

---

## 2. Protocol Sequence

```mermaid
sequenceDiagram
    autonumber
    actor Owner as Owner (Mobile App)
    participant Relay as VanishKey Relay Server
    participant Agent as Desktop Agent (Laptop)
    actor Roommate as Roommate

    Note over Agent: Starts up, generates device X25519 keypair & pairing secret
    Agent->>Relay: WS Connect / Register Pending Device
    Agent-->>Owner: Displays Pairing QR Code
    Owner->>Relay: POST /api/v1/devices/pair (Signed deviceToken issued)
    Relay-->>Agent: Device Paired notification

    Note over Owner,Roommate: Roommate asks for 3-minute access to get a file
    Owner->>Owner: PIN + Biometrics authentication pass
    Owner->>Relay: WS / ACCESS_REQUEST (with ephemeral X25519 Phone PubKey)
    Note over Relay: Enforces Rate Limit (max 3/hour/owner)
    Relay->>Agent: Relays ACCESS_REQUEST
    Agent->>Agent: Runs create_temp_user.ps1 / .sh (Standard user ONLY)
    Agent->>Agent: Calculates Shared Secret via X25519(agentPriv, phonePub)
    Agent->>Agent: Derives AES-256 Key via HKDF-SHA256
    Agent->>Agent: Encrypts {username, password, expires_at} with AES-256-GCM
    Agent->>Relay: WS / ACCESS_RESPONSE (Ciphertext + IV + AuthTag + Agent PubKey)
    Relay->>Owner: Relays ACCESS_RESPONSE (Relay cannot decrypt!)
    Owner->>Owner: Derives shared secret & decrypts payload
    Owner-->>Roommate: Dictates / Shows temporary login credentials
    Roommate->>Agent: Logs into laptop lock screen with temp account
    Note over Agent: Expiry countdown (e.g. 3 mins) elapses
    Agent->>Agent: schtasks / launchd runs delete_temp_user.ps1 / .sh
    Note over Agent: Session killed, SAM user removed, home dir purged!
```

---

## 3. Data Payloads

### Ephemeral Decrypted Credential (Mobile Only)
```json
{
  "username": "VK_Temp_7E12A0",
  "password": "v8K#9d$mP2q!Lz-7A@b4W+eY",
  "created_at": "2026-11-01T03:00:00.000Z",
  "expires_at": "2026-11-01T03:03:00.000Z",
  "duration_seconds": 180
}
```

The relay server only ever witnesses the opaque ciphertext block:
```json
{
  "type": "ACCESS_RESPONSE",
  "requestId": "req_84729482",
  "deviceId": "dev_windows_laptop_1",
  "encryptedPayload": "4dFa3e...",
  "iv": "3mP9...",
  "authTag": "81fE...",
  "agentPublicKey": "qW81..."
}
```
