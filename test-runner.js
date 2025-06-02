#!/usr/bin/env node
const fs = require('fs');
const fsExtra = require('fs-extra');
if (!fsExtra.pathExists) {
  fsExtra.pathExists = async (p) => {
    try { await fs.promises.access(p); return true; } catch { return false; }
  };
}
const path = require('path');

const CacheManager = require('./CacheManager');
const NetworkOptimizer = require('./NetworkOptimizer');
const ErrorRecovery = require('./ErrorRecovery');

const tests = [];
function test(name, fn) { tests.push({name, fn}); }

async function run() {
  let failed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      console.log('✓', t.name);
    } catch (e) {
      failed++;
      console.error('✗', t.name, '-', e.message);
    }
  }
  console.log(`${tests.length - failed}/${tests.length} tests passed.`);
  if (failed) process.exit(1);
}

// CacheManager tests

test('CacheManager atomic operations', async () => {
  const tmp = path.join(__dirname, 'tmp.txt');
  fs.writeFileSync(tmp, 'data');
  const stat = fs.statSync(tmp);
  const cache = {};
  if (!CacheManager.needsSync(tmp, stat, cache)) throw new Error('should need sync');
  CacheManager.updateCacheEntry(cache, tmp, stat);
  if (CacheManager.needsSync(tmp, stat, cache)) throw new Error('should not need sync after update');
  CacheManager.evictCache(cache, 0);
  if (!CacheManager.needsSync(tmp, stat, cache)) throw new Error('should need sync after eviction');
  fs.unlinkSync(tmp);
});

test('CacheManager handles corrupted cache', async () => {
  fs.writeFileSync(CacheManager.CACHE_PATH, 'invalid json');
  const cache = await CacheManager.loadCache();
  if (Object.keys(cache).length !== 0) throw new Error('cache should be empty');
});

// NetworkOptimizer tests

test('NetworkOptimizer isUNCPath', () => {
  if (!NetworkOptimizer.isUNCPath('\\\\server\\share')) throw new Error('UNC path not detected');
  if (NetworkOptimizer.isUNCPath('C:/data')) throw new Error('False UNC detection');
});

test('NetworkOptimizer apply LAN optimizations', () => {
  let cfg = { parallelCopies: 2 };
  cfg = NetworkOptimizer.applyNetworkOptimizations(cfg, { type: 'LAN' });
  if (cfg.parallelCopies < 8) throw new Error('LAN optimization failed');
});

test('NetworkOptimizer apply WAN optimizations', () => {
  let cfg = { parallelCopies: 10 };
  cfg = NetworkOptimizer.applyNetworkOptimizations(cfg, { type: 'WAN' });
  if (cfg.parallelCopies > 2) throw new Error('WAN optimization failed');
});

// ErrorRecovery tests

test('ErrorRecovery retryOperation', async () => {
  let count = 0;
  await ErrorRecovery.retryOperation(async () => {
    count++;
    if (count < 2) throw new Error('fail');
  }, 3);
  if (count !== 2) throw new Error('did not retry correctly');
});

test('ErrorRecovery resumeCopy', async () => {
  const src = path.join(__dirname, 'src.tmp');
  const dest = path.join(__dirname, 'dest.tmp');
  fs.writeFileSync(src, '1234567890');
  fs.writeFileSync(dest, '12345');
  const completed = await ErrorRecovery.resumeCopy(src, dest);
  const full = fs.readFileSync(dest, 'utf8');
  if (!completed || full !== '1234567890') throw new Error('resumeCopy failed');
  fs.unlinkSync(src);
  fs.unlinkSync(dest);
});

test('ErrorRecovery CircuitBreaker opens', async () => {
  const cb = new ErrorRecovery.CircuitBreaker(2, 1000);
  try { await cb.exec(() => { throw new Error('fail'); }); } catch {}
  try { await cb.exec(() => { throw new Error('fail'); }); } catch {}
  let opened = false;
  try { await cb.exec(() => {}); } catch (e) { opened = true; }
  if (!opened) throw new Error('circuit should be open');
});

if (require.main === module) {
  run();
}

