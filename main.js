const path = require('path');
const { app, BrowserWindow } = require('electron');
const Config = require('./lib/Config');
const SyncEngine = require('./lib/SyncEngine');

let mainWindow;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 400,
    height: 280,
    frame: false,
    alwaysOnTop: true,
    transparent: true,
    resizable: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false
    }
  });
  mainWindow.loadFile(path.join(__dirname, 'splash.html'));
}

async function runVisual() {
  const config = new Config();
  const engine = new SyncEngine(config, 'visual');
  createWindow();
  mainWindow.webContents.on('did-finish-load', async () => {
    try {
      await engine.sync();
      mainWindow.webContents.send('update-status', '✅ Terminé');
      setTimeout(() => app.quit(), 1000);
    } catch (err) {
      mainWindow.webContents.send('update-status', '❌ ' + err.message);
      setTimeout(() => app.quit(), 2000);
    }
  });
}

async function runSilent() {
  try {
    const config = new Config();
    const engine = new SyncEngine(config, 'silent');
    await engine.sync();
    console.log('Sync done');
  } catch (err) {
    console.error(err);
  }
}

if (process.argv.includes('--silent')) {
  runSilent();
} else {
  app.whenReady().then(runVisual);
  app.on('window-all-closed', () => app.quit());
}
