#!/usr/bin/env node
const fs = require('fs-extra');
const path = require('path');
const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');

const NetworkOptimizer = require('../NetworkOptimizer');
const TransferManager = require('../TransferManager');
const CacheManager = require('../CacheManager');
const ErrorRecovery = require('../ErrorRecovery');
const TelemetryCollector = require('../monitoring/TelemetryCollector');
const AnalyticsEngine = require('../monitoring/AnalyticsEngine');
const ReportGenerator = require('../monitoring/ReportGenerator');
const HealthChecker = require('../monitoring/HealthChecker');
const AdvancedLogger = require('../logger/AdvancedLogger');
const versionManager = require('../version-manager');
const CliInterface = require('./cli-interface');

NetworkOptimizer.relaunchFromTempIfNeeded();

const argv = yargs(hideBin(process.argv)).argv;
const ui = new CliInterface();
const analytics = new AnalyticsEngine();
const logger = new AdvancedLogger();
let config;

async function loadConfig() {
  const configPath = path.join(__dirname, '..', 'config.json');
  if (!await fs.pathExists(configPath)) {
    throw new Error(`config.json manquant: ${configPath}`);
  }
  config = await fs.readJson(configPath);
}

async function ensureDirectories() {
  if (!await fs.pathExists(config.sourceDirectory)) {
    throw new Error(`Répertoire source introuvable: ${config.sourceDirectory}`);
  }
  await fs.ensureDir(config.targetDirectory);
}

async function scanSourceFiles() {
  const files = [];
  const dir = config.sourceDirectory;
  const entries = await fs.readdir(dir);
  for (const entry of entries) {
    const p = path.join(dir, entry);
    const stat = await fs.stat(p);
    if (stat.isFile()) files.push(p);
  }
  return files;
}

async function copyFileIfNeeded(file, cache) {
  const stat = await fs.stat(file);
  if (!CacheManager.needsSync(file, stat, cache)) return false;
  const dest = path.join(config.targetDirectory, path.basename(file));
  await TransferManager.transferFile(file, dest, { rateLimit: config.rateLimit });
  CacheManager.updateCacheEntry(cache, file, stat);
  return true;
}

async function performSync() {
  ui.showStatus('Début de la synchronisation...');
  const telemetry = new TelemetryCollector({ granularity: config.telemetryGranularity });
  logger.log('info', 'Début de la synchronisation');

  await ensureDirectories();
  const cache = await CacheManager.loadCache();

  const sourceFiles = await scanSourceFiles();
  if (sourceFiles.length === 0) {
    ui.showStatus('⚠️ Aucun fichier à synchroniser');
    return;
  }
  ui.startProgress(sourceFiles.length);

  let completed = 0;
  let copied = 0;
  for (const file of sourceFiles) {
    const wasCopied = await copyFileIfNeeded(file, cache);
    if (wasCopied) copied++;
    completed++;
    ui.updateProgress({
      progress: Math.round(completed / sourceFiles.length * 100),
      current: completed,
      total: sourceFiles.length,
      fileName: path.basename(file),
      copied
    });
    telemetry.recordBatch();
  }

  telemetry.finish();
  analytics.addMetrics(telemetry.metrics);
  ReportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
  CacheManager.evictCache(cache);
  await CacheManager.saveCache(cache);

  if (config.executeAfterSync) {
    ui.showStatus(`🚀 Lancement: ${config.executeAfterSync}`);
    setTimeout(() => {
      require('child_process').spawn(config.executeAfterSync, [], { detached: true });
    }, 1000);
  } else {
    ui.showStatus('✅ Synchronisation terminée');
  }
}

(async () => {
  try {
    await loadConfig();
    ui.showAppInfo({ executeAfterSync: config.executeAfterSync, version: config.version });
    await versionManager.checkForUpdates();
    await performSync();
  } catch (err) {
    ui.showStatus(`❌ Erreur: ${err.message}`);
    process.exit(1);
  }
})();
