# VanishKey (TempKey)

> **Zero-Knowledge, Time-Limited Ephemeral Laptop Access for Shared Rooms & Dorms.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Node: >=20](https://img.shields.io/badge/Node.js-%3E%3D20-green.svg)](https://nodejs.org)
[![Flutter: >=3.19](https://img.shields.io/badge/Flutter-%3E%3D3.19-02569B.svg)](https://flutter.dev)

---

## 1. Problem & Solution

In shared living spaces (e.g. 3 roommates with 1 MacBook and 2 Windows laptops), roommates occasionally need to access a laptop to print a document, email a file, or grab school notes while the owner is away.

- **The Danger:** Sharing the primary account password grants full, permanent disk access, reveals saved browser credentials, and cannot easily be revoked.
- **The VanishKey Solution:** The owner generates an ephemeral, time-limited (2–3 minutes, hard-capped at 5 minutes) unprivileged standard user credential from their phone. The roommate logs in, accesses their files, and when the timer expires, the temporary account, active sessions, and local home folder are **automatically purged and destroyed**.

---

## 2. Security Architecture & Zero-Knowledge Guarantees

```
+-------------------+             +-----------------------+             +------------------------+
|    Mobile App     |             |  Relay Server (Docker)|             |  Desktop Host (Laptop) |
| (PIN + Biometrics)|             |   (Zero-Knowledge Hub)|             |  (System Tray / Daemon)|
+-------------------+             +-----------------------+             +------------------------+
          |                                   |                                     |
          |-------- ACCESS_REQUEST ---------->|                                     |
          |  (Contains Ephemeral X25519 Pub)  |-------- Forward Command ----------->|
          |                                   |                                     |
          |                                   |                               [Executes Script]
          |                                   |                              (create_temp_user)
          |                                   |                                     |
          |                                   |                            [Derives Shared DH Key]
          |                                   |                            [Encrypts: AES-256-GCM]
          |                                   |                                     |
          |                                   |<------- ACCESS_RESPONSE ------------|
          |<-- Relays Encrypted Ciphertext ---|     (Ciphertext + IV + AuthTag)     |
          |                                   |                                     |
    [Decrypts Local]                          |                               [Timer Expires]
 [Reveals 24-char Cred]                       |                              (delete_temp_user)
 [Roommate logs in]                           |                             [Purges Home & Account]
```

1. **Least-Privilege Standard User:** Temporary users are created strictly under the unprivileged `Users` / `staff` groups. Administrative permissions (`Administrators`, `wheel`, `sudo`) are blocked.
2. **Cross-Directory Isolation:** Default OS security and explicit permission hardening prevent the temporary user from reading other users' home folders (`C:\Users\<Owner>` or `/Users/<Owner>`).
3. **End-to-End Cryptography (Zero-Knowledge Relay):** Credentials are exchanged using **Curve25519 (X25519) Diffie-Hellman + HKDF-SHA256 + AES-256-GCM**. The relay server never possesses the private keys and can never decrypt the credentials.
4. **Anti-Abuse Rate Limiting:** Maximum 3 credential generations per hour per owner account enforced at the relay server.
5. **Double Security Gate:** The mobile application requires PIN entry plus device Biometrics (Fingerprint / FaceID) before any access generation can be triggered.

---

## 3. Repository Structure

```
D:\PROJECTS\VanishKey\
├── scripts/
│   ├── windows/
│   │   ├── create_temp_user.ps1       # Administrative PowerShell account creator
│   │   └── delete_temp_user.ps1       # Idempotent cleanup & profile purge script
│   └── macos/
│       ├── create_temp_user.sh        # sysadminctl unprivileged user creator
│       └── delete_temp_user.sh        # launchd cleanup & home directory purge
├── protocol/
│   ├── protocol_spec.json             # Formal JSON Schema specification
│   └── README.md                      # Cryptographic handshake documentation
├── server/
│   ├── src/
│   │   ├── index.js                   # Express + WS server entry
│   │   ├── hub.js                     # Zero-knowledge WebSocket routing hub
│   │   ├── store.js                   # Device pairing & metadata audit store
│   │   ├── rateLimiter.js             # Sliding-window rate limiter (3 req/hr)
│   │   └── logger.js                  # Structured Pino logger
│   ├── Dockerfile                     # Lightweight container build
│   └── package.json
├── agent-cli/
│   ├── src/
│   │   ├── index.js                   # Minimal PoC Desktop CLI Agent
│   │   ├── cryptoHelper.js            # Node.js X25519 & AES-256-GCM suite
│   │   └── scriptRunner.js            # OS script process executor
│   ├── test/
│   │   └── e2e-simulation.js          # Full automated end-to-end test suite
│   └── package.json
├── mobile_app/                        # Flutter Mobile App (Android & iOS)
│   ├── lib/
│   │   ├── main.dart
│   │   ├── screens/                   # PIN lock, Home, QR Scan, Active Credential
│   │   ├── services/                  # Biometrics, Relay WS, Pure Dart Cryptography
│   │   └── models/
│   └── pubspec.yaml
├── desktop_agent/                     # Flutter Desktop Host (Windows & macOS)
│   ├── lib/
│   │   ├── main.dart                  # Tray initialization & window manager
│   │   ├── screens/                   # Host dashboard, QR pairing view, Audit log
│   │   └── services/                  # Script runner, Tray manager, Auto-start
│   ├── packaging/
│   │   ├── windows/installer.iss      # Inno Setup Windows installer config
│   │   └── macos/Entitlements.plist   # macOS Hardened Runtime entitlements
│   └── pubspec.yaml
├── .github/workflows/
│   └── build.yml                      # Multi-platform CI/CD for all 4 targets
├── fastforge.config.yaml              # Fastforge packaging manifest
├── TESTING.md                         # Step-by-step verification guide
└── DISTRIBUTION.md                    # Code signing, Notarization & Sideloading
```

---

## 4. Quickstart Guide

### 4.1 Running the Relay Server
```bash
cd server
npm install
npm start
```
*Or via Docker:*
```bash
docker build -t vanishkey-relay ./server
docker run -d -p 8080:8080 --name vanishkey-relay vanishkey-relay
```

### 4.2 Running the Phase 2 E2E Test Suite
The automated simulation tests pairing, key exchange, encryption/decryption, rate limiting, and zero-knowledge log compliance:
```bash
cd agent-cli
npm install
npm run test-e2e
```

### 4.3 Running the CLI Host Agent
```bash
cd agent-cli
npm start
```

### 4.4 Running the Flutter Mobile App
```bash
cd mobile_app
flutter pub get
flutter run
```

### 4.5 Running the Flutter Desktop Host
```bash
cd desktop_agent
flutter pub get
flutter run -d windows   # On Windows
flutter run -d macos     # On macOS
```

---

## 5. Security & Verification Testing

Refer to [TESTING.md](file:///D:/PROJECTS/VanishKey/TESTING.md) for full procedures on verifying:
- Local account group isolation (`Users` only).
- Access denial when attempting to navigate into `C:\Users\<Owner>` or `/Users/<Owner>`.
- Timed scheduled deletion via `schtasks` (Windows) and `launchd` (macOS).
- Full cleanup of profile registry hives and user home directories.
