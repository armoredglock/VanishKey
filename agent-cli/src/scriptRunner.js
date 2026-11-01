import { spawn } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Project root is two levels up from src/
const PROJECT_ROOT = path.resolve(__dirname, '../../');

export async function createTemporaryUser(durationMinutes = 3) {
  const isWindows = process.platform === 'win32';
  const isMac = process.platform === 'darwin';

  if (!isWindows && !isMac && process.env.NODE_ENV !== 'test') {
    throw new Error(`Unsupported OS platform: ${process.platform}. VanishKey supports Windows and macOS.`);
  }

  // If in test or emulation mode without admin privileges, allow dry-run simulation
  if (process.env.VANISHKEY_MOCK_SCRIPTS === 'true') {
    const fakeHex = Math.random().toString(16).substring(2, 8).toUpperCase();
    return {
      success: true,
      username: `VK_Mock_${fakeHex}`,
      password: `vK!${Math.random().toString(36).substring(2, 12)}#9Qx$`,
      created_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + durationMinutes * 60000).toISOString(),
      duration_minutes: durationMinutes,
      duration_seconds: durationMinutes * 60
    };
  }

  return new Promise((resolve, reject) => {
    let cmd = '';
    let args = [];

    if (isWindows) {
      const scriptPath = path.join(PROJECT_ROOT, 'scripts', 'windows', 'create_temp_user.ps1');
      cmd = 'powershell.exe';
      args = [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-DurationMinutes', String(durationMinutes)
      ];
    } else {
      const scriptPath = path.join(PROJECT_ROOT, 'scripts', 'macos', 'create_temp_user.sh');
      cmd = 'bash';
      args = [scriptPath, '--duration', String(durationMinutes)];
    }

    const proc = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdoutData = '';
    let stderrData = '';

    proc.stdout.on('data', (d) => { stdoutData += d.toString(); });
    proc.stderr.on('data', (d) => { stderrData += d.toString(); });

    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`Script exited with code ${code}: ${stderrData || stdoutData}`));
      }

      try {
        // Find JSON block in output
        const jsonMatch = stdoutData.match(/\{[\s\S]*\}/);
        if (!jsonMatch) {
          return reject(new Error(`Script did not return valid JSON: ${stdoutData}`));
        }
        const parsed = JSON.parse(jsonMatch[0]);
        if (!parsed.success && parsed.error) {
          return reject(new Error(parsed.error));
        }
        resolve(parsed);
      } catch (err) {
        reject(new Error(`Failed to parse script output: ${err.message}. Output was: ${stdoutData}`));
      }
    });

    proc.on('error', (err) => {
      reject(new Error(`Failed to start script process: ${err.message}`));
    });
  });
}

export async function deleteTemporaryUser(username) {
  const isWindows = process.platform === 'win32';
  const isMac = process.platform === 'darwin';

  if (process.env.VANISHKEY_MOCK_SCRIPTS === 'true') {
    return { success: true, status: 'deleted', username, mock: true };
  }

  return new Promise((resolve, reject) => {
    let cmd = '';
    let args = [];

    if (isWindows) {
      const scriptPath = path.join(PROJECT_ROOT, 'scripts', 'windows', 'delete_temp_user.ps1');
      cmd = 'powershell.exe';
      args = [
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', scriptPath,
        '-Username', username
      ];
    } else {
      const scriptPath = path.join(PROJECT_ROOT, 'scripts', 'macos', 'delete_temp_user.sh');
      cmd = 'bash';
      args = [scriptPath, '--username', username];
    }

    const proc = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'] });

    let stdoutData = '';
    let stderrData = '';

    proc.stdout.on('data', (d) => { stdoutData += d.toString(); });
    proc.stderr.on('data', (d) => { stderrData += d.toString(); });

    proc.on('close', (code) => {
      if (code !== 0) {
        return reject(new Error(`Delete script exited with code ${code}: ${stderrData || stdoutData}`));
      }
      try {
        const jsonMatch = stdoutData.match(/\{[\s\S]*\}/);
        resolve(jsonMatch ? JSON.parse(jsonMatch[0]) : { success: true });
      } catch (err) {
        resolve({ success: true, raw: stdoutData });
      }
    });
  });
}
