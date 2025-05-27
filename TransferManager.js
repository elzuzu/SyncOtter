const fs = require('fs-extra');
const path = require('path');
const zlib = require('zlib');
const { pipeline, Transform } = require('stream');
const { promisify } = require('util');
const ErrorRecovery = require('./ErrorRecovery');

const pump = promisify(pipeline);

class Throttle extends Transform {
  constructor(rate) {
    super();
    this.rate = rate; // bytes per second
    this.remaining = 0;
    this.last = Date.now();
  }
  _transform(chunk, enc, cb) {
    const now = Date.now();
    const elapsed = now - this.last;
    this.remaining -= elapsed * this.rate / 1000;
    if (this.remaining < 0) this.remaining = 0;
    this.remaining += chunk.length;
    this.last = now;
    const delay = this.remaining / this.rate * 1000;
    setTimeout(() => cb(null, chunk), delay);
  }
}

async function compressCopy(src, dest) {
  const temp = dest + '.gz';
  await pump(fs.createReadStream(src), zlib.createGzip(), fs.createWriteStream(temp));
  await pump(fs.createReadStream(temp), zlib.createGunzip(), fs.createWriteStream(dest));
  await fs.remove(temp);
}

async function chunkedCopy(src, dest, opts = {}) {
  const { chunkSize = 8 * 1024 * 1024, rateLimit } = opts;
  const read = fs.createReadStream(src, { highWaterMark: chunkSize });
  const write = fs.createWriteStream(dest);
  const streams = [read];
  if (rateLimit) streams.push(new Throttle(rateLimit));
  streams.push(write);
  await pump(...streams);
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
      await fs.copy(src, dest);
    }
  });
}

module.exports = { transferFile };
