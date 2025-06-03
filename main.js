const { app, BrowserWindow, ipcMain } = require('electron');
const fs = require('fs-extra');
const path = require('path');
const crypto = require('crypto');
const { spawn, exec } = require('child_process');
const TelemetryCollector = require('./monitoring/TelemetryCollector');
const AnalyticsEngine = require('./monitoring/AnalyticsEngine');
const ReportGenerator = require('./monitoring/ReportGenerator');
const HealthChecker = require('./monitoring/HealthChecker');
const AdvancedLogger = require('./logger/AdvancedLogger');
const versionManager = require('./version-manager');

// Modules d'optimisation réseau
const NetworkOptimizer = require('./NetworkOptimizer');
const { activeOperations } = NetworkOptimizer;
const CacheManager = require('./CacheManager');
const ErrorRecovery = require('./ErrorRecovery');
const { ensureDirectories, scanSourceFiles, copyFileIfNeeded } = require('./shared/sync-core');
const Ajv = require('ajv');

// Relance depuis le dossier temporaire si besoin
NetworkOptimizer.relaunchFromTempIfNeeded();

// Configuration Electron sécurisée
app.commandLine.appendSwitch('disable-site-isolation-trials');

let mainWindow;
let config;
let telemetry;
const analytics = new AnalyticsEngine();
const reportGenerator = new ReportGenerator();
const logger = new AdvancedLogger();

const IPC_MAX_RETRIES = 3;
const pendingRetries = new Map();
function safeSend(channel, data, attempt = 0) {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  try {
    mainWindow.webContents.send(channel, data);
    pendingRetries.delete(channel);
  } catch (err) {
    if (attempt < IPC_MAX_RETRIES) {
      clearTimeout(pendingRetries.get(channel));
      const id = setTimeout(() => safeSend(channel, data, attempt + 1), 200);
      pendingRetries.set(channel, id);
    } else {
      pendingRetries.delete(channel);
      console.error(`IPC send failed for ${channel}:`, err);
    }
  }
}

let shutdownTimer = null;
let isShuttingDown = false;

function scheduleShutdown(delay = 1500) {
  if (shutdownTimer) clearTimeout(shutdownTimer);
  shutdownTimer = setTimeout(() => {
    shutdownTimer = null;
    if (config && config.executeAfterSync && fs.existsSync(config.executeAfterSync)) {
      spawn(config.executeAfterSync, [], { detached: true, stdio: 'ignore' }).unref();
    }
    forceCleanShutdown();
  }, delay);
}

async function forceCleanShutdown() {
  if (isShuttingDown) return;
  isShuttingDown = true;
  console.log('🧹 Nettoyage forcé...');

  if (shutdownTimer) {
    clearTimeout(shutdownTimer);
    shutdownTimer = null;
  }

  pendingRetries.forEach(id => clearTimeout(id));
  pendingRetries.clear();

  if (telemetry) {
    telemetry.removeAllListeners();
    try { telemetry.finish(); } catch {}
    analytics.addMetrics(telemetry.metrics);
    telemetry = null;
  }

  try {
    const health = await HealthChecker.basicReport(config);
    reportGenerator.generate({ metrics: telemetry?.metrics || {}, health });
  } catch (err) {
    console.error('Erreur lors du graceful shutdown:', err);
  }

  if (mainWindow && !mainWindow.isDestroyed()) {
    mainWindow.destroy();
  }

  process.removeAllListeners();

  activeOperations.forEach(proc => {
    try { proc.kill(); } catch {}
  });

  setTimeout(() => {
    console.log('💀 Sortie forcée');
    process.exit(0);
  }, 2000);

  app.quit();
}

ipcMain.on('request-shutdown', forceCleanShutdown);


// Charger la configuration externe (optimisé)
async function loadConfig() {
  try {
    let configPath;

    if (app.isPackaged) {
      const exeDir = path.dirname(process.execPath);
      configPath = path.join(exeDir, 'config.json');
    } else {
      configPath = path.join(__dirname, 'config.json');
    }

    console.log(`📄 Chargement config: ${configPath}`);

    if (!fs.existsSync(configPath)) {
      throw new Error(`Fichier config.json introuvable: ${configPath}`);
    }

    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const ajv = new Ajv();
    const schema = {
      type: 'object',
      required: ['sourceDirectory', 'targetDirectory'],
      properties: {
        sourceDirectory: { type: 'string', minLength: 1 },
        targetDirectory: { type: 'string', minLength: 1 },
        parallelCopies: { type: 'integer', minimum: 1, maximum: 64 }
      }
    };
    const validate = ajv.compile(schema);
    if (!validate(config)) {
      throw new Error(`Config invalide: ${JSON.stringify(validate.errors)}`);
    }
    console.log('✅ Configuration chargée');

    const unc = NetworkOptimizer.isUNCPath(config.sourceDirectory)
      ? config.sourceDirectory
      : NetworkOptimizer.isUNCPath(config.targetDirectory)
        ? config.targetDirectory
        : null;
    if (unc) {
      const info = await NetworkOptimizer.detectNetworkInfo(unc);
      if (info) {
        console.log(`🌐 Réseau ${info.type} - ${info.latencyMs || '?'}ms`);
        config = NetworkOptimizer.applyNetworkOptimizations(config, info);
      }
    }

  } catch (error) {
    console.error('❌ Erreur config.json:', error.message);

    if (app.isPackaged) {
      console.error('💡 Solution: Placez config.json à côté de l\'exe SyncOtter');
    }

    forceCleanShutdown();
  }
}

// Créer le splash screen (optimisé pour performance)
function createSplashWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 320, // Augmenté pour offrir plus d'espace
    frame: false,
    alwaysOnTop: true,
    transparent: true,
    resizable: false,
    center: true,
    show: false, // Optimisation: afficher après chargement
    webPreferences: {
      nodeIntegration: false,
      contextIsolation: true,
      enableRemoteModule: false,
      allowRunningInsecureContent: false,
      preload: path.join(__dirname, 'src', 'preload.js')
    }
  });
  mainWindow.loadFile(path.join(__dirname, 'web', 'splash.html'));
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
  });
}


async function performSync() {
  try {
    console.log('🦦 Début de la synchronisation...');
    telemetry = new TelemetryCollector({ granularity: config.telemetryGranularity });
    telemetry.on('metric', (m) => logger.log('debug', 'metric', m));
    logger.log('info', 'Début de la synchronisation');
    safeSend('update-status', 'Vérification des répertoires...');

    await ensureDirectories(config);

    const cache = await CacheManager.loadCache();

    safeSend('update-status', 'Analyse des fichiers...');

    const sourceFiles = await scanSourceFiles(config);
    console.log(`📁 ${sourceFiles.length} fichiers trouvés`);

    if (sourceFiles.length === 0) {
      safeSend('update-status', '⚠️ Aucun fichier à synchroniser');
      scheduleShutdown(2000);
      return;
    }

    let completed = 0;
    let copied = 0;

    async function processBatch(files) {
      const promises = files.map(async (file) => {
        const wasCopied = await copyFileIfNeeded(file, config, cache, telemetry);
        if (wasCopied) copied++;

        completed++;
        const progress = Math.round((completed / sourceFiles.length) * 100);
        const fileName = path.basename(file);

        safeSend('update-progress', {
          progress,
          current: completed,
          total: sourceFiles.length,
          fileName,
          copied
        });
      });

      await Promise.all(promises);
      telemetry.recordBatch();
    }

    const batchSize = config.parallelCopies || 4;
    for (let i = 0; i < sourceFiles.length; i += batchSize) {
      const batch = sourceFiles.slice(i, i + batchSize);
      await processBatch(batch);
    }

    console.log(`✅ Synchronisation terminée: ${copied} fichiers copiés`);
    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    const health = await HealthChecker.basicReport(config);
    const reportFile = reportGenerator.generate({ metrics: telemetry.metrics, health });
    logger.log('info', `Rapport généré: ${reportFile}`);
    logger.log('info', `Synchronisation terminée: ${copied} fichiers`);
    safeSend('telemetry-summary', telemetry.metrics);
    CacheManager.evictCache(cache);
    await CacheManager.saveCache(cache);

    if (config.executeAfterSync && fs.existsSync(config.executeAfterSync)) {
      const appDisplayName = config.appName || path.basename(config.executeAfterSync, '.exe');
      safeSend('update-status', `🚀 Lancement: ${appDisplayName}`);
      console.log(`🚀 Lancement: ${config.executeAfterSync}`);
      try {
        spawn(config.executeAfterSync, [], { detached: true, stdio: 'ignore' }).unref();
      } catch (e) {
        console.error('Erreur lancement application:', e);
      }
      scheduleShutdown(1500);
    } else {
      if (config.executeAfterSync) {
        safeSend('update-status', '⚠️ Application introuvable');
      } else {
        safeSend('update-status', '✅ Synchronisation terminée');
      }
      scheduleShutdown(2000);
    }

  } catch (error) {
    console.error('❌ Erreur synchronisation:', error);
    safeSend('update-status', `❌ Erreur: ${error.message}`);
    telemetry.recordError();
    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    const errorHealth = await HealthChecker.basicReport(config);
    reportGenerator.generate({ metrics: telemetry.metrics, health: errorHealth });
    scheduleShutdown(3000);
  }
}

app.whenReady().then(async () => {
  loadConfig();
  versionManager.checkForUpdates().catch(err =>
    console.error('Update check failed:', err)
  );

  createSplashWindow();

  const health = await HealthChecker.basicReport(config);
  logger.log('info', 'Health check', health);
  safeSend('health-report', health);

  NetworkOptimizer.registerTempCleanup(app);


  setImmediate(() => {
    performSync();
  });
});

app.on('window-all-closed', () => {
  forceCleanShutdown();
});

app.on('before-quit', () => {
  if (!isShuttingDown) forceCleanShutdown();
});

const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  forceCleanShutdown();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}
