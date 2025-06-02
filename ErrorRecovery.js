const fs = require('fs-extra');
const crypto = require('crypto');
const path = require('path');
const { exec } = require('child_process');

async function retryOperation(fn, retries = 3, delay = 500) {
  let attempt = 0;
  while (attempt < retries) {
    try {
      return await fn();
    } catch (err) {
      attempt++;
      if (attempt >= retries) throw err;
      await new Promise((res) => setTimeout(res, delay * Math.pow(2, attempt)));
    }
  }
}

function checkDiskSpace(dir, required) {
  return new Promise((resolve) => {
    let cmd;
    if (process.platform === 'win32') {
      const drive = path.parse(path.resolve(dir)).root.replace(/\\$/, '').replace(/'/g, "''");
      cmd = `wmic logicaldisk where Caption='${drive}' get FreeSpace /value`;
    } else {
      cmd = `df -Pk \"${dir}\"`;
    }
    exec(cmd, { timeout: 5000 }, (err, stdout) => {
      if (err) return resolve(false);
      let free = 0;
      if (process.platform === 'win32') {
        const m = stdout.match(/FreeSpace=(\d+)/);
        if (m) free = parseInt(m[1], 10);
      } else {
        const lines = stdout.trim().split(/\n/);
        const parts = lines.pop().trim().split(/\s+/);
        if (parts[3]) free = parseInt(parts[3], 10) * 1024;
      }
      resolve(free >= required);
    });
  });
}

async function fileHash(file) {
  const hash = crypto.createHash('md5');
  const stream = fs.createReadStream(file);
  return new Promise((resolve, reject) => {
    stream.on('data', d => hash.update(d));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  }).finally(() => {
    try { stream.close(); } catch {}
  });
}

async function verifyIntegrity(src, dest) {
  if (!await fs.pathExists(dest)) return false;
  const [h1, h2] = await Promise.all([fileHash(src), fileHash(dest)]);
  return h1 === h2;
}

async function resumeCopy(src, dest) {
  const stat = await fs.stat(src);
  const destDir = path.dirname(dest);
  await fs.ensureDir(destDir);
  try {
    await fs.access(destDir, fs.constants.W_OK);
  } catch (err) {
    throw new Error(`Cannot write to directory: ${destDir}`);
  }
  const hasSpace = await checkDiskSpace(destDir, stat.size);
  if (!hasSpace) throw new Error('Insufficient disk space');

  let written = 0;
  if (await fs.pathExists(dest)) {
    const destStat = await fs.stat(dest);
    written = destStat.size;
  }

  const read = fs.createReadStream(src, { start: written });
  const write = fs.createWriteStream(dest, { flags: written ? 'r+' : 'w', start: written });

  try {
    await new Promise((resolve, reject) => {
      read.pipe(write).on('finish', resolve).on('error', reject);
    });
  } finally {
    read.close();
    write.close();
  }

  const final = await fs.stat(dest);
  return final.size === stat.size;
}

class CircuitBreaker {
  constructor(limit = 5, timeout = 30000) {
    this.failures = 0;
    this.limit = limit;
    this.timeout = timeout;
    this.openUntil = 0;
  }
  async exec(fn) {
    if (Date.now() < this.openUntil) throw new Error('Circuit open');
    try {
      const res = await fn();
      this.failures = 0;
      this.openUntil = 0;
      return res;
    } catch (err) {
      this.failures++;
      if (this.failures >= this.limit) {
        this.openUntil = Date.now() + this.timeout;
        console.error(`Circuit opened for ${this.timeout}ms`);
      }
      throw err;
    }
  }
}

module.exports = {
  retryOperation,
  verifyIntegrity,
  resumeCopy,
  CircuitBreaker
};
