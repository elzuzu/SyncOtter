const fs = require('fs-extra');
const crypto = require('crypto');

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

async function fileHash(file) {
  const hash = crypto.createHash('md5');
  return new Promise((resolve, reject) => {
    const stream = fs.createReadStream(file);
    stream.on('data', (d) => hash.update(d));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

async function verifyIntegrity(src, dest) {
  if (!await fs.pathExists(dest)) return false;
  const [h1, h2] = await Promise.all([fileHash(src), fileHash(dest)]);
  return h1 === h2;
}

async function resumeCopy(src, dest) {
  const stat = await fs.stat(src);
  let written = 0;
  if (await fs.pathExists(dest)) {
    const destStat = await fs.stat(dest);
    written = destStat.size;
  }
  const read = fs.createReadStream(src, { start: written });
  const write = fs.createWriteStream(dest, { flags: written ? 'r+' : 'w', start: written });
  await new Promise((resolve, reject) => {
    read.pipe(write).on('finish', resolve).on('error', reject);
  });
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
      return res;
    } catch (err) {
      this.failures++;
      if (this.failures >= this.limit) {
        this.openUntil = Date.now() + this.timeout;
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
