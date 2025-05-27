const fs = require('fs-extra');
const path = require('path');

class Config {
  constructor() {
    const baseDir = process.env.PORTABLE_EXECUTABLE_DIR || __dirname;
    const configPath = path.join(baseDir, 'config.json');
    if (!fs.existsSync(configPath)) {
      throw new Error(`Configuration file missing: ${configPath}`);
    }
    this.path = configPath;
    Object.assign(this, fs.readJsonSync(configPath));
  }
}

module.exports = Config;
