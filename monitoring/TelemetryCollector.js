const { EventEmitter } = require('events');
const os = require('os');

class TelemetryCollector extends EventEmitter {
  constructor(options = {}) {
    super();
    this.metrics = {
      startTime: Date.now(),
      filesCopied: 0,
      errors: 0,
      bytesCopied: 0,
      batches: 0,
      ...options.initialMetrics
    };
    this.granularity = options.granularity || 'summary';
    this.logs = [];
    this.maxLogs = options.maxLogs || 1000;
  }

  recordFileCopied(bytes) {
    this.metrics.filesCopied += 1;
    if (bytes) this.metrics.bytesCopied += bytes;
    this._addLog({ type: 'fileCopied', bytes });
    this.emit('metric', { type: 'fileCopied', bytes });
  }

  recordError() {
    this.metrics.errors += 1;
    this._addLog({ type: 'error' });
    this.emit('metric', { type: 'error' });
  }

  recordBatch() {
    this.metrics.batches += 1;
    this._addLog({ type: 'batch' });
  }

  finish() {
    this.metrics.endTime = Date.now();
    this.metrics.durationMs = this.metrics.endTime - this.metrics.startTime;
    this.metrics.throughput = this.metrics.durationMs > 0 ?
      (this.metrics.bytesCopied / (this.metrics.durationMs / 1000)) : 0;
    this.metrics.averageFileSize = this.metrics.filesCopied ?
      (this.metrics.bytesCopied / this.metrics.filesCopied) : 0;
    this.metrics.memoryUsage = process.memoryUsage().rss;
    this.metrics.hostname = os.hostname();
    this.metrics.logs = this.logs.slice();
    this.emit('finished', this.metrics);
  }

  _addLog(entry) {
    if (this.logs.length >= this.maxLogs) this.logs.shift();
    this.logs.push({ time: Date.now(), ...entry });
  }
}

module.exports = TelemetryCollector;
