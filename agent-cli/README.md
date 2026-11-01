# VanishKey Desktop Agent CLI (Proof of Concept)

The CLI Desktop Agent is a lightweight Node.js proof-of-concept that demonstrates the end-to-end VanishKey lifecycle on Windows and macOS.

## Features
- **Zero-Knowledge Architecture:** Implements X25519 Diffie-Hellman key exchange and AES-256-GCM authenticated encryption. The relay server never sees credentials.
- **Platform Script Runner:** Dispatches unprivileged user creation scripts (`create_temp_user.ps1` on Windows, `create_temp_user.sh` on macOS).
- **Persistent Device Identity:** Generates device ID and cryptographic keys saved locally to `agent-config.json`.
- **Local Audit Log:** Writes all actions, sessions, and cleanup events to `agent-audit.log`.

## Installation & Setup

1. Install dependencies:
   ```bash
   cd agent-cli
   npm install
   ```

2. Start the agent:
   ```bash
   npm start
   ```

3. Run the automated End-to-End Simulation Suite:
   ```bash
   npm run test-e2e
   ```
