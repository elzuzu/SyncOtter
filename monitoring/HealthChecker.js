const fs = require('fs');
const os = require('os');
const path = require('path');
const dns = require('dns');
const util = require('util');
const { execSync } = require('child_process');

const lookup = util.promisify(dns.lookup);

class HealthChecker {
  static checkDiskSpace(targetDirectory) {
    try {
      let free = null;
      let size = null;
      if (process.platform === 'win32') {
        const drive = path.parse(path.resolve(targetDirectory)).root.replace(/\\$/, '');
        const out = execSync(`wmic logicaldisk where Caption='${drive}' get FreeSpace,Size /value`, { encoding: 'utf8', timeout: 5000 });
        const mFree = out.match(/FreeSpace=(\d+)/);
        if (mFree) free = parseInt(mFree[1], 10);
        const mSize = out.match(/Size=(\d+)/);
        if (mSize) size = parseInt(mSize[1], 10);
      } else {
        const out = execSync(`df -Pk \"${targetDirectory}\"`, { encoding: 'utf8', timeout: 5000 });
        const lines = out.trim().split(/\n/);
        const parts = lines.pop().trim().split(/\s+/);
        if (parts[1]) size = parseInt(parts[1], 10) * 1024;
        if (parts[3]) free = parseInt(parts[3], 10) * 1024;
      }
      return { free, size };
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
