const fs = require('fs-extra');
const path = require('path');
const crypto = require('crypto');

class DeltaScanner {
  constructor(sourceDir, cache) {
    this.sourceDir = sourceDir;
    this.cache = cache;
    this.changes = [];
  }

  async _scanDir(dir) {
    const entries = await fs.readdir(dir);
    for (const entry of entries) {
      const full = path.join(dir, entry);
      const stat = await fs.stat(full);
      if (stat.isDirectory()) {
        await this._scanDir(full);
      } else {
        if (this.cache.needsUpdate(full, stat)) {
          const hash = await this._fullHash(full);
          this.changes.push({ path: full, size: stat.size, hash });
          this.cache.update(full, stat);
        }
      }
    }
  }

  _fullHash(filePath) {
    return new Promise((resolve, reject) => {
      const hash = crypto.createHash('md5');
      const stream = fs.createReadStream(filePath);
      stream.on('data', d => hash.update(d));
      stream.on('end', () => resolve(hash.digest('hex')));
      stream.on('error', reject);
    });
  }

  async scan() {
    await this._scanDir(this.sourceDir);
    return this.changes;
  }
}

module.exports = DeltaScanner;
