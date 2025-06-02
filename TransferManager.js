const fs = require('fs-extra');
const path = require('path');
const zlib = require('zlib');
const { Transform } = require('stream');
const { pipeline } = require('stream/promises');
const ErrorRecovery = require('./ErrorRecovery');

async function transferFileWithCleanup(src, dest) {
  let readStream = null;
  let writeStream = null;
  try {
    readStream = fs.createReadStream(src);
    writeStream = fs.createWriteStream(dest);
    await pipeline(readStream, writeStream);
  } finally {
    if (readStream && !readStream.destroyed) readStream.destroy();
    if (writeStream && !writeStream.destroyed) writeStream.destroy();
  }
}

class Throttle extends Transform {
  constructor(rate) {
    super();
    this.rate = rate; // bytes per second
    this.remaining = 0;
    this.last = Date.now();
  }
  _transform(chunk, enc, cb) {
    try {
      const now = Date.now();
      const elapsed = now - this.last;
      this.remaining -= elapsed * this.rate / 1000;
      if (this.remaining < 0) this.remaining = 0;
      this.remaining += chunk.length;
      this.last = now;
      const delay = this.remaining / this.rate * 1000;
      setTimeout(() => cb(null, chunk), delay);
    } catch (err) {
      cb(err);
    }
  }
}

async function compressCopy(src, dest) {
  const temp = dest + '.gz';
  const read1 = fs.createReadStream(src);
  const gzip = zlib.createGzip();
  const writeTemp = fs.createWriteStream(temp);
  try {
    await pipeline(read1, gzip, writeTemp);
    const read2 = fs.createReadStream(temp);
    const gunzip = zlib.createGunzip();
    const writeDest = fs.createWriteStream(dest);
    await pipeline(read2, gunzip, writeDest);
  } finally {
    try { await fs.remove(temp); } catch {}
  }
}

async function chunkedCopy(src, dest, opts = {}) {
  const { chunkSize = 8 * 1024 * 1024, rateLimit } = opts;
  const read = fs.createReadStream(src, { highWaterMark: chunkSize });
  const write = fs.createWriteStream(dest);
  const throttle = rateLimit ? new Throttle(rateLimit) : null;
  const streams = throttle ? [read, throttle, write] : [read, write];
  await pipeline(...streams);
}

async function transferFile(src, dest, opts = {}) {
  await fs.ensureDir(path.dirname(dest));
  return ErrorRecovery.retryOperation(async () => {
    const stat = await fs.stat(src);
    if (stat.size < 100 * 1024) {
      await compressCopy(src, dest);
    } else if (stat.size > 50 * 1024 * 1024) {
      await chunkedCopy(src, dest, opts);
    } else {
      await transferFileWithCleanup(src, dest);
    }
  });
}

module.exports = { transferFile, transferFileWithCleanup };
