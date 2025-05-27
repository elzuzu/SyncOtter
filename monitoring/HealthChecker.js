const fs = require('fs');
const os = require('os');
const path = require('path');

class HealthChecker {
  static checkDiskSpace(targetDirectory) {
    try {
      const stats = fs.statSync(targetDirectory);
      return stats.isDirectory();
    } catch {
      return false;
    }
  }

  static basicReport(config) {
    return {
      hostname: os.hostname(),
      platform: os.platform(),
      freeMemory: os.freemem(),
      totalMemory: os.totalmem(),
      targetAccessible: this.checkDiskSpace(config.targetDirectory)
    };
  }
}

module.exports = HealthChecker;
