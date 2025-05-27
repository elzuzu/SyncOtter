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

const IPC_MAX_RETRIES = 3;
function safeSend(channel, data, attempt = 0) {
  if (!mainWindow || mainWindow.isDestroyed()) return;
  try {
    mainWindow.webContents.send(channel, data);
  } catch (err) {
    if (attempt < IPC_MAX_RETRIES) {
      setTimeout(() => safeSend(channel, data, attempt + 1), 200);
    } else {
      console.error(`IPC send failed for ${channel}:`, err);
    }
  }
}

let shuttingDown = false;
function gracefulShutdown() {
  if (shuttingDown) return;
  shuttingDown = true;
  try {
    telemetry?.finish();
    if (telemetry) analytics.addMetrics(telemetry.metrics);
    reportGenerator.generate({ metrics: telemetry?.metrics || {}, health: HealthChecker.basicReport(config) });
  } catch (err) {
    console.error('Erreur lors du graceful shutdown:', err);
  }
  app.quit();
}

ipcMain.on('request-shutdown', gracefulShutdown);

// Vérifier et tuer les processus SyncOtter existants
async function killExistingProcesses() {
  return new Promise((resolve) => {
    const currentPid = process.pid;
    const exePath = process.execPath.toLowerCase();

    exec('tasklist /FI "IMAGENAME eq SyncOtter*" /FO CSV', (error, stdout) => {
      if (error || !stdout.includes('SyncOtter')) {
        return resolve(false); // Pas de processus existant
      }

      const lines = stdout.split('\n').slice(1);
      const processes = lines
        .filter(line => line.includes('SyncOtter'))
        .map(line => {
          const parts = line.split('\",\"');
          return {
            name: parts[0]?.replace('"', ''),
            pid: parseInt(parts[1]) || 0
          };
        })
        .filter(proc => proc.pid && proc.pid !== currentPid);

      if (processes.length === 0) {
        return resolve(false);
      }

      const checks = processes.map(p => new Promise(res => {
        exec(`wmic process where processid=${p.pid} get CommandLine /FORMAT:CSV`, (e, out) => {
          if (!e && out.toLowerCase().includes(exePath)) {
            res(p.pid);
          } else {
            res(null);
          }
        });
      }));

      Promise.all(checks).then(validPids => {
        const pidsToKill = validPids.filter(Boolean);
        if (pidsToKill.length === 0) {
          return resolve(false);
        }

        console.log('🔄 SyncOtter déjà en cours, arrêt des processus existants...');
        logger.log('info', 'Instance existante détectée, arrêt en cours');

        exec(`taskkill /F /PID ${pidsToKill.join(' ')}`, (killError) => {
          if (!killError) {
            console.log('✅ Processus existants fermés');
            logger.log('info', 'Processus existants fermés');
          }
          setTimeout(() => resolve(true), 500);
        });
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

    const cache = await CacheManager.loadCache();

    safeSend('update-status', 'Analyse des fichiers...');

    const sourceFiles = await scanSourceFiles();
    console.log(`📁 ${sourceFiles.length} fichiers trouvés`);

    if (sourceFiles.length === 0) {
      safeSend('update-status', '⚠️ Aucun fichier à synchroniser');
      setTimeout(() => gracefulShutdown(), 2000);
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

    if (config.executeAfterSync && fs.existsSync(config.executeAfterSync)) {
      const appDisplayName = config.appName || path.basename(config.executeAfterSync, '.exe');
      safeSend('update-status', `🚀 Lancement: ${appDisplayName}`);
      setTimeout(() => {
        console.log(`🚀 Lancement: ${config.executeAfterSync}`);
        try {
          spawn(config.executeAfterSync, [], { detached: true });
        } catch (e) {
          console.error('Erreur lancement application:', e);
        }
        gracefulShutdown();
      }, 1500);
    } else {
      if (config.executeAfterSync) {
        safeSend('update-status', '⚠️ Application introuvable');
      } else {
        safeSend('update-status', '✅ Synchronisation terminée');
      }
      setTimeout(() => gracefulShutdown(), 2000);
    }

  } catch (error) {
    console.error('❌ Erreur synchronisation:', error);
    safeSend('update-status', `❌ Erreur: ${error.message}`);
    telemetry.recordError();
    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    reportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
    setTimeout(() => gracefulShutdown(), 3000);
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

app.on('window-all-closed', () => {
  gracefulShutdown();
});

app.on('before-quit', () => {
  if (!shuttingDown) gracefulShutdown();
});

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
