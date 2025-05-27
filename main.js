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

// Vérifier et tuer les processus SyncOtter existants
async function killExistingProcesses() {
  return new Promise((resolve) => {
    exec('tasklist /FI "IMAGENAME eq SyncOtter*" /FO CSV', (error, stdout) => {
      if (error || !stdout.includes('SyncOtter')) {
        resolve(false); // Pas de processus existant
        return;
      }
      
      logger.log("info", "Instance existante détectée, arrêt en cours");
      
      exec('taskkill /F /IM "SyncOtter*" /T', (killError) => {
        if (!killError) {
          logger.log('info', 'Processus existants fermés');
        }
        // Attendre un peu pour être sûr
        setTimeout(() => resolve(true), 500);
      });
    });
  });
}

// Créer les répertoires nécessaires
async function ensureDirectories() {
  try {
    // Vérifier et créer le répertoire source (optionnel)
    if (!await fs.pathExists(config.sourceDirectory)) {
      console.log(`⚠️  Répertoire source inexistant: ${config.sourceDirectory}`);
      throw new Error(`Répertoire source introuvable: ${config.sourceDirectory}`);
    }
    
    // Créer le répertoire de destination s'il n'existe pas
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
function loadConfig() {
  try {
    let configPath;
    
    // Détecter si on est en mode développement ou packagé
    if (app.isPackaged) {
      // Mode packagé : chercher config.json à côté de l'exe
      const exeDir = path.dirname(process.execPath);
      configPath = path.join(exeDir, 'config.json');
    } else {
      // Mode développement : chercher dans le répertoire du projet
      configPath = path.join(__dirname, 'config.json');
    }
    
    console.log(`📄 Chargement config: ${configPath}`);
    
    if (!fs.existsSync(configPath)) {
      throw new Error(`Fichier config.json introuvable: ${configPath}`);
    }
    
    config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    console.log('✅ Configuration chargée');
    
  } catch (error) {
    console.error('❌ Erreur config.json:', error.message);
    
    // En mode packagé, donner des instructions claires
    if (app.isPackaged) {
      console.error('💡 Solution: Placez config.json à côté de l\'exe SyncOtter');
    }
    
    app.quit();
  }
}

// Créer le splash screen (optimisé pour performance)
function createSplashWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 280, // Hauteur augmentée pour la section app
    frame: false,
    alwaysOnTop: true,
    transparent: true,
    resizable: false,
    center: true,
    show: false, // Optimisation: afficher après chargement
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      enableRemoteModule: false,
      webSecurity: false,
      backgroundThrottling: false // Pas de throttling pour performance
    }
  });

  const splashPath = path.join(__dirname, 'splash.html');
  mainWindow.loadFile(splashPath);
  
  // Afficher après chargement complet
  mainWindow.once('ready-to-show', () => {
    mainWindow.show();
    
    // Envoyer les infos de l'application
    setTimeout(() => {
      sendAppInfo();
    }, 200);
  });
}

// Envoyer les informations de l'application au splash
function sendAppInfo() {
  const appData = {
    appName: config.appName || null,
    appDescription: config.appDescription || null,
    executeAfterSync: config.executeAfterSync || null
  };
  
  mainWindow.webContents.send('app-info', appData);
}

// Calculer le hash MD5 d'un fichier
function getFileHash(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5');
    const stream = fs.createReadStream(filePath);
    
    stream.on('data', data => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', reject);
  });
}

// Vérifier si un fichier doit être exclu
function shouldExclude(filePath) {
  const relativePath = path.relative(config.sourceDirectory, filePath);
  
  // Vérifier les répertoires exclus
  for (const excludeDir of config.excludeDirectories) {
    if (relativePath.includes(excludeDir)) {
      return true;
    }
  }
  
  // Vérifier les patterns exclus
  for (const pattern of config.excludePatterns) {
    const regex = new RegExp(pattern.replace(/\*/g, '.*'));
    if (regex.test(path.basename(filePath))) {
      return true;
    }
  }
  
  return false;
}

// Scanner tous les fichiers source
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

// Copier un fichier avec vérification hash
async function copyFileIfNeeded(sourceFile) {
  const relativePath = path.relative(config.sourceDirectory, sourceFile);
  const targetFile = path.join(config.targetDirectory, relativePath);
  
  try {
    // Créer le répertoire cible si nécessaire
    await fs.ensureDir(path.dirname(targetFile));
    
    // Vérifier si le fichier existe et s'il est identique
    if (await fs.pathExists(targetFile)) {
      const sourceHash = await getFileHash(sourceFile);
      const targetHash = await getFileHash(targetFile);
      
      if (sourceHash === targetHash) {
        return false; // Pas de copie nécessaire
      }
    }
    
    // Copier le fichier
    const stats = await fs.stat(sourceFile);
    await fs.copy(sourceFile, targetFile);
    telemetry.recordFileCopied(stats.size);
    return true; // Fichier copié
    
  } catch (error) {
    telemetry.recordError();
    console.error(`Erreur copie ${sourceFile}:`, error);
    return false;
  }
}

// Synchronisation parallélisée (avec vérifications)
async function performSync() {
  try {
    telemetry = new TelemetryCollector({ granularity: config.telemetryGranularity });
    telemetry.on('metric', (m) => logger.log('debug', 'metric', m));
    logger.log('info', 'Début de la synchronisation');
    console.log('🦦 Début de la synchronisation...');
    mainWindow.webContents.send('update-status', 'Vérification des répertoires...');
    
    // Vérifier et créer les répertoires
    await ensureDirectories();
    
    mainWindow.webContents.send('update-status', 'Analyse des fichiers...');
    
    const sourceFiles = await scanSourceFiles();
    logger.log('info', `Fichiers trouvés: ${sourceFiles.length}`);
    console.log(`📁 ${sourceFiles.length} fichiers trouvés`);
    
    if (sourceFiles.length === 0) {
      mainWindow.webContents.send('update-status', '⚠️ Aucun fichier à synchroniser');
      setTimeout(() => app.quit(), 2000);
      return;
    }
    
    let completed = 0;
    let copied = 0;
    
    // Fonction pour traiter un batch de fichiers
    async function processBatch(files) {
      const promises = files.map(async (file) => {
        const wasCopied = await copyFileIfNeeded(file);
        if (wasCopied) copied++;
        
        completed++;
        const progress = Math.round((completed / sourceFiles.length) * 100);
        const fileName = path.basename(file);
        
        mainWindow.webContents.send('update-progress', {
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
    
    // Traiter par batch parallèles
    const batchSize = config.parallelCopies || 4;
    for (let i = 0; i < sourceFiles.length; i += batchSize) {
      const batch = sourceFiles.slice(i, i + batchSize);
      await processBatch(batch);
    }

    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    const reportFile = reportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
    logger.log('info', `Rapport généré: ${reportFile}`);
    logger.log('info', `Synchronisation terminée: ${copied} fichiers`);
    mainWindow.webContents.send('telemetry-summary', telemetry.metrics);
    console.log(`✅ Synchronisation terminée: ${copied} fichiers copiés`);
    
    // Lancer l'exécutable si configuré
    if (config.executeAfterSync) {
      const appDisplayName = config.appName || path.basename(config.executeAfterSync, '.exe');
      mainWindow.webContents.send('update-status', `🚀 Lancement: ${appDisplayName}`);
      setTimeout(() => {
        console.log(`🚀 Lancement: ${config.executeAfterSync}`);
        spawn(config.executeAfterSync, [], { detached: true });
        app.quit();
      }, 1500); // Un peu plus de temps pour voir le message
    } else {
      mainWindow.webContents.send('update-status', '✅ Synchronisation terminée');
      setTimeout(() => app.quit(), 2000);
    }
    
  } catch (error) {
    console.error('❌ Erreur synchronisation:', error);
    telemetry.recordError();
    telemetry.finish();
    analytics.addMetrics(telemetry.metrics);
    reportGenerator.generate({ metrics: telemetry.metrics, health: HealthChecker.basicReport(config) });
    mainWindow.webContents.send('update-status', `❌ Erreur: ${error.message}`);
    setTimeout(() => app.quit(), 3000);
  }
}

// Événements Electron (optimisés avec gestion processus)
app.whenReady().then(async () => {
  loadConfig();
  
  // Vérifier et tuer les processus existants
  const hadExistingProcess = await killExistingProcesses();
  
  createSplashWindow();

  // Rapport santé initial
  const health = HealthChecker.basicReport(config);
  logger.log('info', 'Health check', health);
  mainWindow.webContents.send('health-report', health);
  
  // Message informatif si processus tué
  if (hadExistingProcess) {
    setTimeout(() => {
      mainWindow.webContents.send('update-status', '🔄 Processus précédent fermé...');
    }, 200);
  }
  
  // Démarrer la sync immédiatement
  setImmediate(() => {
    performSync();
  });
});

app.on('window-all-closed', () => {
  app.quit();
});

// Gestion instance unique
const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  // Une autre instance est déjà ouverte, on quitte
  app.quit();
} else {
  app.on('second-instance', () => {
    // Quelqu'un essaie de relancer l'app
    if (mainWindow) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.focus();
    }
  });
}

// Pas besoin d'activate sur Windows
if (process.platform !== 'win32') {
  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createSplashWindow();
    }
  });
}