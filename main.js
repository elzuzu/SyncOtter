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
const TransferManager = require('./TransferManager');
const CacheManager = require('./CacheManager');
const ErrorRecovery = require('./ErrorRecovery');

// Relance depuis le dossier temporaire si besoin
NetworkOptimizer.relaunchFromTempIfNeeded();

// Désactiver les warnings et optimiser les performances
process.env.ELECTRON_DISABLE_SECURITY_WARNINGS = 'true';
app.commandLine.appendSwitch('--no-sandbox');
app.commandLine.appendSwitch('--disable-web-security');

let mainWindow;
let config;
let telemetry;
const analytics = new AnalyticsEngine();
const reportGenerator = new ReportGenerator();
const logger = new AdvancedLogger();
let shuttingDown = false;

process.on('SIGINT', gracefulShutdown);
process.on('SIGTERM', gracefulShutdown);
app.on('before-quit', gracefulShutdown);

function safeSend(channel, data, attempt = 0) {
  try {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.webContents.send(channel, data);
      return;
    }
  } catch (err) {
    logger.log('error', `IPC send failed on ${channel}: ${err.message}`);
  }
  if (attempt < 3) {
    setTimeout(() => safeSend(channel, data, attempt + 1), 300);
  }
}

async function gracefulShutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    safeSend('update-status', 'Fermeture...');
    await CacheManager.saveCache();
  } catch (err) {
    logger.log('error', `Graceful shutdown failed: ${err.message}`);
  }
  app.quit();
}

// Vérifier et tuer les processus SyncOtter existants
async function killExistingProcesses() {
  return new Promise((resolve) => {
    const currentPid = process.pid;
    const exePath = process.execPath.toLowerCase();

    exec('wmic process where "name like \"SyncOtter%\"" get ProcessId,ExecutablePath /FORMAT:CSV', (error, stdout) => {
      if (error || !stdout) {
        resolve(false);
        return;
      }

      const lines = stdout.trim().split(/\r?\n/).slice(1);
      const processes = lines
        .map(line => {
          const parts = line.split(',');
          const pid = parseInt(parts[2], 10);
          const pathExe = (parts[1] || '').trim().toLowerCase();
          return { pid, path: pathExe };
        })
        .filter(p => p.pid && p.pid !== currentPid && p.path === exePath);

      if (processes.length === 0) {
        resolve(false);
        return;
      }

      console.log('🔄 SyncOtter déjà en cours, arrêt des processus existants...');
      logger.log('info', 'Instance existante détectée, arrêt en cours');

      const pidsToKill = processes.map(p => p.pid).join(' ');
      exec(`taskkill /F /PID ${pidsToKill}`, (killError) => {
        if (!killError) {
          console.log('✅ Processus existants fermés');
          logger.log('info', 'Processus existants fermés');
        }
        setTimeout(() => resolve(true), 500);
      });
    });
  });
}

// Créer les répertoires nécessaires
async function ensureDirectories() {
  try {
    if (!await fs.pathExists(config.sourceDirectory)) {
      console.log(`⚠️  Répertoire source inexistant: ${config.sourceDirectory}`);
      throw new Error(`Répertoire source introuvable: ${config.sourceDirectory}`);
    }

    if (!await fs.pathExists(config.targetDirectory)) {
      console.log(`📁 Création du répertoire de destination: ${config.targetDirectory}`);
      await fs.ensureDir(config.targetDirectory);
      console.log('✅ Répertoire de destination créé');
    }

    return true;
  } catch (error) {
    console.error('❌ Erreur répertoires:', error.message);
    throw error;
  }
}

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

    gracefulShutdown();
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
      nodeIntegration: true,
      contextIsolation: false
    }
  });
  mainWindow.loadFile(path.join(__dirname, 'splash.html'));
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    safeSend('app-info', {
      appName: config.appName,
      appDescription: config.appDescription,
      executeAfterSync: config.executeAfterSync
    });
  });
}

function shouldExclude(filePath) {
  const rel = path.relative(config.sourceDirectory, filePath);
  const parts = rel.split(path.sep);
  if (parts.some(p => config.excludeDirectories?.includes(p))) return true;
  if (config.excludePatterns) {
    return config.excludePatterns.some(pattern => {
      const regex = new RegExp(pattern.replace(/\*/g, '.*'));
      return regex.test(path.basename(filePath));
    });
  }
  return false;
}

async function scanSourceFiles() {
  const files = [];

  async function scanDir(dir) {
    const items = await fs.readdir(dir);

    for (const item of items) {
      const fullPath = path.join(dir, item);
      const stat = await fs.stat(fullPath);

      if (stat.isDirectory()) {
        if (!shouldExclude(fullPath)) {
          await scanDir(fullPath);
        }
      } else {
        if (!shouldExclude(fullPath)) {
          files.push(fullPath);
        }
      }
    }
  }

  await scanDir(config.sourceDirectory);
  return files;
}

async function copyFileIfNeeded(sourceFile, cache) {
  const relativePath = path.relative(config.sourceDirectory, sourceFile);
  const targetFile = path.join(config.targetDirectory, relativePath);

  try {
    await fs.ensureDir(path.dirname(targetFile));
    const stat = await fs.stat(sourceFile);

    if (await fs.pathExists(targetFile)) {
      if (!CacheManager.needsSync(sourceFile, stat, cache) && await ErrorRecovery.verifyIntegrity(sourceFile, targetFile)) {
        return false;
      }
    }
    await TransferManager.transferFile(sourceFile, targetFile, { rateLimit: config.rateLimit });
    CacheManager.updateCacheEntry(cache, sourceFile, stat);
    telemetry.recordFileCopied(stat.size);
    return true;

  } catch (error) {
    console.error(`Erreur copie ${sourceFile}:`, error);
    telemetry.recordError();
    return false;
  }
}

async function performSync() {
  try {
    console.log('🦦 Début de la synchronisation...');
    telemetry = new TelemetryCollector({ granularity: config.telemetryGranularity });
    telemetry.on('metric', (m) => logger.log('debug', 'metric', m));
    logger.log('info', 'Début de la synchronisation');
    safeSend('update-status', 'Vérification des répertoires...');

    await ensureDirectories();

    let cache = {};
    try {
      cache = await CacheManager.loadCache();
    } catch (err) {
      logger.log('error', `Cache load failed: ${err.message}`);
      cache = {};
    }

    safeSend('update-status', 'Analyse des fichiers...');

    let sourceFiles = [];
    try {
      sourceFiles = await scanSourceFiles();
    } catch (err) {
      logger.log('error', `Scan failed: ${err.message}`);
      throw err;
    }
    console.log(`📁 ${sourceFiles.length} fichiers trouvés`);

    if (sourceFiles.length === 0) {
      safeSend('update-status', '⚠️ Aucun fichier à synchroniser');
      setTimeout(gracefulShutdown, 2000);
      return;
    }

    let completed = 0;
    let copied = 0;

    async function processBatch(files) {
      const promises = files.map(async (file) => {
        const wasCopied = await copyFileIfNeeded(file, cache);
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
    const reportFile = reportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
    logger.log('info', `Rapport généré: ${reportFile}`);
    logger.log('info', `Synchronisation terminée: ${copied} fichiers`);
    safeSend('telemetry-summary', telemetry.metrics);
    CacheManager.evictCache(cache);
    await CacheManager.saveCache(cache);

    if (config.executeAfterSync) {
      const appDisplayName = config.appName || path.basename(config.executeAfterSync, '.exe');
      if (fs.existsSync(config.executeAfterSync)) {
        safeSend('update-status', `🚀 Lancement: ${appDisplayName}`);
        setTimeout(() => {
          try {
            console.log(`🚀 Lancement: ${config.executeAfterSync}`);
            spawn(config.executeAfterSync, [], { detached: true });
          } catch (e) {
            logger.log('error', `Spawn failed: ${e.message}`);
          }
          gracefulShutdown();
        }, 1500);
      } else {
        safeSend('update-status', `❌ Exécutable introuvable: ${config.executeAfterSync}`);
        logger.log('error', `Executable not found: ${config.executeAfterSync}`);
        setTimeout(gracefulShutdown, 3000);
      }
    } else {
      safeSend('update-status', '✅ Synchronisation terminée');
      setTimeout(gracefulShutdown, 2000);
    }

  } catch (error) {
    console.error('❌ Erreur synchronisation:', error);
    safeSend('update-status', `❌ Erreur: ${error.message}`);
    telemetry.recordError();
    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    reportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
    setTimeout(gracefulShutdown, 3000);
  }
}

app.whenReady().then(async () => {
  loadConfig();
  versionManager.checkForUpdates().catch(err =>
    console.error('Update check failed:', err)
  );

  const hadExistingProcess = await killExistingProcesses();

  createSplashWindow();

  const health = HealthChecker.basicReport(config);
  logger.log('info', 'Health check', health);
  safeSend('health-report', health);

  NetworkOptimizer.registerTempCleanup(app);

  if (hadExistingProcess) {
    setTimeout(() => {
      safeSend('update-status', '🔄 Processus précédent fermé...');
    }, 200);
  }

  setImmediate(() => {
    performSync();
  });
});

app.on('window-all-closed', gracefulShutdown);

const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  gracefulShutdown();
} else {
  app.on('second-instance', () => {
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}
