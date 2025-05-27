const fs = require('fs-extra');
const path = require('path');
const os = require('os');
const { exec } = require('child_process');

function isUNCPath(p) {
  return /^\\\\/.test(p);
}

function extractHost(uncPath) {
  return uncPath.replace(/^\\\\/, '').split('\\')[0];
}

async function pingHost(host) {
  return new Promise((resolve) => {
    if (!host) return resolve(null);
    const cmd = process.platform === 'win32' ? `ping -n 3 ${host}` : `ping -c 3 ${host}`;
    exec(cmd, (err, stdout) => {
      if (err) return resolve(null);
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
  const latency = await pingHost(host);
  let type = 'UNKNOWN';
  if (latency != null) {
    if (latency < 10) type = 'LAN';
    else if (latency < 100) type = 'VPN';
    else type = 'WAN';
  }
  return { host, latencyMs: latency, type };
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
  const tempDir = path.join(os.tmpdir(), `SyncOtter-${Date.now()}`);
  fs.ensureDirSync(tempDir);
  const exeName = path.basename(exePath);
  const destExe = path.join(tempDir, exeName);
  fs.copySync(exePath, destExe);
  const configPath = path.join(path.dirname(exePath), 'config.json');
  if (fs.existsSync(configPath)) {
    fs.copySync(configPath, path.join(tempDir, 'config.json'));
  }
  const args = process.argv.slice(1);
  const child = require('child_process').spawn(destExe, args, {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, SYNCOTTER_TEMP: tempDir }
  });
  child.unref();
  process.exit(0);
}

function registerTempCleanup(app) {
  const dir = process.env.SYNCOTTER_TEMP;
  if (!dir) return;
  app.on('quit', () => {
    try { fs.removeSync(dir); } catch (e) { /* ignore */ }
  });
}

module.exports = {
  isUNCPath,
  detectNetworkInfo,
  applyNetworkOptimizations,
  relaunchFromTempIfNeeded,
  registerTempCleanup
};
