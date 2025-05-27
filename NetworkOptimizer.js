const fs = require('fs-extra');
const path = require('path');
const os = require('os');
const { exec, spawn } = require('child_process');

function isUNCPath(p) {
  return /^\\\\/.test(p);
}

function extractHost(uncPath) {
  return uncPath.replace(/^\\\\/, '').split('\\')[0];
}

async function pingHost(host, timeout = 5000) {
  return new Promise((resolve) => {
    if (!host) return resolve(null);
    const cmd = process.platform === 'win32' ? `ping -n 3 ${host}` : `ping -c 3 ${host}`;
    exec(cmd, { timeout }, (err, stdout) => {
      if (err) {
        console.error(`ping error for ${host}:`, err.message);
        return resolve(null);
      }
      const regexWin = /Average = ([0-9]+)ms/;
      const regexUnix = /= ([0-9.]+)\/\d+\/\d+/;
      let match = stdout.match(regexWin);
      if (!match) match = stdout.match(regexUnix);
      if (match) return resolve(parseFloat(match[1]));
      resolve(null);
    });
  });
}

async function detectNetworkInfo(uncPath) {
  if (!isUNCPath(uncPath)) return null;
  const host = extractHost(uncPath);
  try {
    const latency = await pingHost(host);
    let type = 'UNKNOWN';
    if (latency != null) {
      if (latency < 10) type = 'LAN';
      else if (latency < 100) type = 'VPN';
      else type = 'WAN';
    }
    return { host, latencyMs: latency, type };
  } catch (e) {
    console.error('detectNetworkInfo error:', e.message);
    return { host, latencyMs: null, type: 'UNKNOWN' };
  }
}

function applyNetworkOptimizations(config, networkInfo) {
  if (!networkInfo) return config;
  const clone = { ...config };
  if (!clone.parallelCopies) clone.parallelCopies = 4;
  if (networkInfo.type === 'LAN') clone.parallelCopies = Math.max(clone.parallelCopies, 8);
  else if (networkInfo.type === 'VPN') clone.parallelCopies = Math.min(clone.parallelCopies, 4);
  else clone.parallelCopies = Math.min(clone.parallelCopies, 2);
  return clone;
}

function relaunchFromTempIfNeeded() {
  const exePath = process.execPath;
  if (!isUNCPath(exePath) || process.env.SYNCOTTER_TEMP) return;
  if (exePath.startsWith(os.tmpdir())) return; // avoid recursive relaunch
  try {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'SyncOtter-'));
    const exeName = path.basename(exePath);
    const destExe = path.join(tempDir, exeName);
    fs.copyFileSync(exePath, destExe);
    const configPath = path.join(path.dirname(exePath), 'config.json');
    if (fs.existsSync(configPath)) {
      fs.copyFileSync(configPath, path.join(tempDir, 'config.json'));
    }
    const args = process.argv.slice(1);
    console.log(`Relaunching from temp: ${destExe}`);
    const child = spawn(destExe, args, {
      detached: true,
      stdio: 'ignore',
      env: { ...process.env, SYNCOTTER_TEMP: tempDir }
    });
    child.unref();
    process.exit(0);
  } catch (err) {
    console.error('Failed to relaunch from temp:', err.message);
  }
}

function registerTempCleanup(app) {
  const dir = process.env.SYNCOTTER_TEMP;
  if (!dir) return;
  app.on('quit', () => {
    try {
      fs.removeSync(dir);
      console.log(`Cleaned temp dir ${dir}`);
    } catch (e) {
      console.error('Temp cleanup error:', e.message);
    }
  });
}

module.exports = {
  isUNCPath,
  detectNetworkInfo,
  applyNetworkOptimizations,
  relaunchFromTempIfNeeded,
  registerTempCleanup
};
