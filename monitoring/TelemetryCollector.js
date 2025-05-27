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
  }

  recordFileCopied(bytes) {
    this.metrics.filesCopied += 1;
    if (bytes) this.metrics.bytesCopied += bytes;
    this.emit('metric', { type: 'fileCopied', bytes });
  }

  recordError() {
    this.metrics.errors += 1;
    this.emit('metric', { type: 'error' });
  }

  recordBatch() {
    this.metrics.batches += 1;
  }

  finish() {
    this.metrics.endTime = Date.now();
    this.metrics.durationMs = this.metrics.endTime - this.metrics.startTime;
    this.metrics.throughput = this.metrics.durationMs > 0 ?
      (this.metrics.bytesCopied / (this.metrics.durationMs / 1000)) : 0;
    this.metrics.hostname = os.hostname();
    this.emit('finished', this.metrics);
  }
}

module.exports = TelemetryCollector;
