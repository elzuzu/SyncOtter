class AnalyticsEngine {
  constructor() {
    this.records = [];
  }

  addMetrics(metrics) {
    this.records.push(metrics);
  }

  getTrend() {
    if (this.records.length < 2) return null;
    const last = this.records[this.records.length - 1];
    const prev = this.records[this.records.length - 2];
    return {
      deltaFiles: last.filesCopied - prev.filesCopied,
      deltaDuration: last.durationMs - prev.durationMs,
      deltaErrors: last.errors - prev.errors
    };
  }
}

module.exports = AnalyticsEngine;
