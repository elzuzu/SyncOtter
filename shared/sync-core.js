const fs = require('fs-extra');
const path = require('path');
const TransferManager = require('../TransferManager');
const CacheManager = require('../CacheManager');
const ErrorRecovery = require('../ErrorRecovery');

function shouldExclude(filePath, config) {
  const rel = path.relative(config.sourceDirectory, filePath);
  const parts = rel.split(path.sep);
  if (config.excludeDirectories && parts.some(p => config.excludeDirectories.includes(p))) return true;
  if (config.excludePatterns) {
    return config.excludePatterns.some(pattern => {
      const regex = new RegExp(pattern.replace(/\*/g, '.*'));
      return regex.test(path.basename(filePath));
    });
  }
  return false;
}

async function ensureDirectories(config) {
  if (!await fs.pathExists(config.sourceDirectory)) {
    throw new Error(`Répertoire source introuvable: ${config.sourceDirectory}`);
  }
  await fs.ensureDir(config.targetDirectory);
}

async function scanSourceFiles(config) {
  const files = [];
  async function scanDir(dir) {
    const items = await fs.readdir(dir);
    for (const item of items) {
      const fullPath = path.join(dir, item);
      const stat = await fs.stat(fullPath);
      if (stat.isDirectory()) {
        if (!shouldExclude(fullPath, config)) await scanDir(fullPath);
      } else {
        if (!shouldExclude(fullPath, config)) files.push(fullPath);
      }
    }
  }
  await scanDir(config.sourceDirectory);
  return files;
}

async function copyFileIfNeeded(file, config, cache, telemetry) {
  const relativePath = path.relative(config.sourceDirectory, file);
  const targetFile = path.join(config.targetDirectory, relativePath);
  try {
    await fs.ensureDir(path.dirname(targetFile));
    const stat = await fs.stat(file);
    if (await fs.pathExists(targetFile)) {
      if (!CacheManager.needsSync(file, stat, cache) && await ErrorRecovery.verifyIntegrity(file, targetFile)) {
        return false;
      }
    }
    await TransferManager.transferFile(file, targetFile, { rateLimit: config.rateLimit });
    CacheManager.updateCacheEntry(cache, file, stat);
    if (telemetry) telemetry.recordFileCopied(stat.size);
    return true;
  } catch (err) {
    if (telemetry) telemetry.recordError();
    return false;
  }
}

module.exports = { ensureDirectories, scanSourceFiles, copyFileIfNeeded };
