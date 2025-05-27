const fs = require('fs-extra');
const os = require('os');
const path = require('path');

const CACHE_PATH = path.join(os.tmpdir(), 'syncotter-cache.json');

async function loadCache() {
  try {
    if (await fs.pathExists(CACHE_PATH)) return fs.readJson(CACHE_PATH);
  } catch (_) {}
  return {};
}

async function saveCache(cache) {
  try {
    const tmp = CACHE_PATH + '.tmp';
    await fs.writeJson(tmp, cache);
    await fs.move(tmp, CACHE_PATH, { overwrite: true });
  } catch (_) {}
}

function entryKey(filePath) {
  return path.resolve(filePath);
}

function needsSync(filePath, stat, cache) {
  const key = entryKey(filePath);
  const entry = cache[key];
  if (!entry) return true;
  return entry.mtime !== stat.mtimeMs || entry.size !== stat.size;
}

function updateCacheEntry(cache, filePath, stat) {
  const key = entryKey(filePath);
  cache[key] = { mtime: stat.mtimeMs, size: stat.size, lastUse: Date.now() };
}

function evictCache(cache, maxEntries = 1000) {
  const keys = Object.keys(cache);
  if (keys.length <= maxEntries) return;
  const entries = keys.map(k => [k, cache[k]]);
  entries.sort((a, b) => a[1].lastUse - b[1].lastUse);
  for (let i = 0; i < entries.length - maxEntries; i++) {
    delete cache[entries[i][0]];
  }
}

module.exports = {
  CACHE_PATH,
  loadCache,
  saveCache,
  needsSync,
  updateCacheEntry,
  evictCache
};
