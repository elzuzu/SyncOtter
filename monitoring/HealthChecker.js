const fs = require('fs');
const os = require('os');
const dns = require('dns');
const util = require('util');

const lookup = util.promisify(dns.lookup);

class HealthChecker {
  static checkDiskSpace(targetDirectory) {
    try {
      const stats = fs.statfsSync(targetDirectory);
      return {
        free: Number(stats.bavail) * stats.bsize,
        size: Number(stats.blocks) * stats.bsize
      };
    } catch {
      return { free: null, size: null };
    }
  }

  static checkPermissions(directory) {
    try {
      fs.accessSync(directory, fs.constants.R_OK | fs.constants.W_OK);
      return 'read-write';
    } catch {
      try {
        fs.accessSync(directory, fs.constants.R_OK);
        return 'read-only';
      } catch {
        return 'none';
      }
    }
  }

  static async checkNetwork() {
    try {
      await lookup('example.com');
      return true;
    } catch {
      return false;
    }
  }

  static async basicReport(config) {
    return {
      hostname: os.hostname(),
      platform: os.platform(),
      freeMemory: os.freemem(),
      totalMemory: os.totalmem(),
      targetDisk: this.checkDiskSpace(config.targetDirectory),
      sourcePermissions: this.checkPermissions(config.sourceDirectory),
      targetPermissions: this.checkPermissions(config.targetDirectory),
      networkReachable: await this.checkNetwork()
    };
  }
}

module.exports = HealthChecker;
