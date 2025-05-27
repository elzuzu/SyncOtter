const path = require('path');
const fs = require('fs-extra');
const MetadataCache = require('./MetadataCache');
const DeltaScanner = require('./DeltaScanner');
const WorkerPool = require('./WorkerPool');

class SyncEngine {
  constructor(config, mode = 'auto') {
    this.config = config;
    this.mode = mode === 'auto' ? this.detectMode() : mode;
    const baseDir = process.env.PORTABLE_EXECUTABLE_DIR || __dirname;
    this.cache = new MetadataCache(baseDir);
    this.pool = new WorkerPool(path.join(__dirname, 'FileWorker.js'), this.getConcurrency());
    this.progress = { total: 0, done: 0 };
  }

  detectMode() {
    if (process.argv.includes('--silent')) return 'silent';
    if (process.argv.includes('--visual')) return 'visual';
    const fromNetwork = /^\\\\/.test(process.execPath);
    return fromNetwork ? 'network' : 'turbo';
  }

  getConcurrency() {
    switch (this.mode) {
      case 'turbo': return 16;
      case 'network': return 4;
      default: return 8;
    }
  }

  async sync() {
    const changes = await this.scan();
    this.progress.total = changes.length;
    for (const change of changes) {
      await this.copy(change);
    }
    this.cache.save();
    this.pool.destroy();
  }

  async scan() {
    const scanner = new DeltaScanner(this.config.sourceDirectory, this.cache);
    const changes = await scanner.scan();
    return changes.map(c => ({ source: c.path, target: path.join(this.config.targetDirectory, path.relative(this.config.sourceDirectory, c.path)), size: c.size }));
  }

  copy(change) {
    return new Promise((resolve, reject) => {
      const send = (task) => {
        this.pool.run(task).then(msg => {
          if (msg.retry) {
            send({ source: task.source, target: task.target, attempt: msg.attempt });
          } else if (msg.success) {
            this.progress.done++;
            resolve();
          } else {
            reject(new Error(msg.error));
          }
        }).catch(reject);
      };
      send(change);
    });
  }
}

module.exports = SyncEngine;
