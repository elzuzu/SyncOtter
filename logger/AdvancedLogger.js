const fs = require('fs');
const path = require('path');

class AdvancedLogger {
  constructor(logDir = 'logs', maxSize = 1024 * 1024) {
    this.logDir = logDir;
    this.maxSize = maxSize;
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
    this.currentFile = path.join(logDir, 'syncotter.log');
  }

  log(level, message, data = {}) {
    const entry = {
      timestamp: new Date().toISOString(),
      level,
      message,
      ...data
    };
    const json = JSON.stringify(entry) + '\n';
    this.rotateIfNeeded();
    fs.appendFileSync(this.currentFile, json);
  }

  rotateIfNeeded() {
    try {
      const stats = fs.statSync(this.currentFile);
      if (stats.size >= this.maxSize) {
        const rotated = this.currentFile.replace('.log', `-${Date.now()}.log`);
        fs.renameSync(this.currentFile, rotated);
      }
    } catch {}
  }
}

module.exports = AdvancedLogger;
