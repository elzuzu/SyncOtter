const fs = require('fs-extra');
const path = require('path');
const crypto = require('crypto');

class MetadataCache {
  constructor(baseDir) {
    this.cacheDir = path.join(baseDir, '.cache');
    this.cacheFile = path.join(this.cacheDir, 'metadata.json');
    fs.ensureDirSync(this.cacheDir);
    this.data = {};
    if (fs.existsSync(this.cacheFile)) {
      try {
        this.data = fs.readJsonSync(this.cacheFile);
      } catch {
        this.data = {};
      }
    }
  }

  _quickHash(filePath) {
    const fd = fs.openSync(filePath, 'r');
    const buffer = Buffer.alloc(Math.min(1024, fs.statSync(filePath).size));
    fs.readSync(fd, buffer, 0, buffer.length, 0);
    fs.closeSync(fd);
    return crypto.createHash('md5').update(buffer).digest('hex');
  }

  needsUpdate(filePath, stat) {
    const entry = this.data[filePath];
    if (!entry) return true;
    if (entry.size !== stat.size || entry.mtime !== stat.mtimeMs) return true;
    const quickHash = this._quickHash(filePath);
    return entry.quickHash !== quickHash;
  }

  update(filePath, stat) {
    this.data[filePath] = {
      size: stat.size,
      mtime: stat.mtimeMs,
      quickHash: this._quickHash(filePath)
    };
  }

  save() {
    fs.writeJsonSync(this.cacheFile, this.data);
  }
}

module.exports = MetadataCache;
