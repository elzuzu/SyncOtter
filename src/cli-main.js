#!/usr/bin/env node
const fs = require('fs-extra');
const path = require('path');
const yargs = require('yargs');
const { hideBin } = require('yargs/helpers');

const NetworkOptimizer = require('../NetworkOptimizer');
const CacheManager = require('../CacheManager');
const ErrorRecovery = require('../ErrorRecovery');
const TelemetryCollector = require('../monitoring/TelemetryCollector');
const AnalyticsEngine = require('../monitoring/AnalyticsEngine');
const ReportGenerator = require('../monitoring/ReportGenerator');
const HealthChecker = require('../monitoring/HealthChecker');
const AdvancedLogger = require('../logger/AdvancedLogger');
const versionManager = require('../version-manager');
const CliInterface = require('./cli-interface');
const { ensureDirectories, scanSourceFiles, copyFileIfNeeded } = require('../shared/sync-core');

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


async function performSync() {
  ui.showStatus('Début de la synchronisation...');
  const telemetry = new TelemetryCollector({ granularity: config.telemetryGranularity });
  logger.log('info', 'Début de la synchronisation');

  await ensureDirectories(config);
  const cache = await CacheManager.loadCache();

  const sourceFiles = await scanSourceFiles(config);
  if (sourceFiles.length === 0) {
    ui.showStatus('⚠️ Aucun fichier à synchroniser');
    return;
  }
  ui.startProgress(sourceFiles.length);

  let completed = 0;
  let copied = 0;
  for (const file of sourceFiles) {
    const wasCopied = await copyFileIfNeeded(file, config, cache, telemetry);
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
  const health = await HealthChecker.basicReport(config);
  ReportGenerator.generate({ metrics: telemetry.metrics, health });
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
