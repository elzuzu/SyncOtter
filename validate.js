#!/usr/bin/env node
const fs = require('fs');
const path = require('path');

const dryRun = process.argv.includes('--dry-run');
let hasError = false;

function log(msg) { console.log(msg); }
function error(msg) { console.error('ERROR:', msg); hasError = true; }

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (e) {
    error(`Cannot read ${file}: ${e.message}`);
    return null;
  }
}

function listFiles(dir) {
  let results = [];
  for (const item of fs.readdirSync(dir)) {
    if (item === 'node_modules' || item === '.git') continue;
    const full = path.join(dir, item);
    const stat = fs.statSync(full);
    if (stat.isDirectory()) results = results.concat(listFiles(full));
    else results.push(full);
  }
  return results;
}

function checkPackageLock() {
  const pkg = readJson('package.json');
  if (!fs.existsSync('package-lock.json')) {
    log('package-lock.json missing, skipping lock check');
    return;
  }
  const lock = readJson('package-lock.json');
  if (!pkg || !lock) return;
  const deps = Object.assign({}, pkg.dependencies, pkg.devDependencies);
  for (const d of Object.keys(deps)) {
    if (!lock.dependencies || !lock.dependencies[d]) {
      error(`Dependency ${d} missing from package-lock.json`);
    }
  }
}

function checkInstalledDeps() {
  const pkg = readJson('package.json');
  if (!pkg) return;
  if (!fs.existsSync('node_modules')) {
    log('node_modules missing, skipping dependency check');
    return;
  }
  const deps = Object.assign({}, pkg.dependencies, pkg.devDependencies);
  for (const dep of Object.keys(deps)) {
    const dir = path.join('node_modules', dep);
    if (!fs.existsSync(dir)) {
      error(`Dependency ${dep} not installed`);
    }
  }
}

function checkRequirePaths() {
  const jsFiles = listFiles('.').filter(f => /\.([jt])s$/.test(f));
  for (const file of jsFiles) {
    const content = fs.readFileSync(file, 'utf8');
    const regex = /require\(['"](.+?)['"]\)/g;
    let match;
    while ((match = regex.exec(content))) {
      const req = match[1];
      if (req.startsWith('./') || req.startsWith('../')) {
        const base = path.resolve(path.dirname(file), req);
        if (!fs.existsSync(base) &&
            !fs.existsSync(base + '.js') &&
            !fs.existsSync(base + '.json') &&
            !fs.existsSync(base + '.ts')) {
          error(`Invalid require path ${req} in ${file}`);
        }
      }
    }
  }
}

function checkAssets() {
  const requiredAssets = [
    'splash.html',
    'config.exemple.json',
    'src/preload.ts',
    'src/cli-main.js'
  ];
  for (const asset of requiredAssets) {
    if (!fs.existsSync(asset)) {
      error(`Missing required file: ${asset}`);
    }
  }
  // Vérifier que l'icône existe ou peut être générée
  const iconPath = 'src/assets/app-icon.ico';
  if (!fs.existsSync(iconPath)) {
    const assetsDir = 'src/assets';
    if (!fs.existsSync(assetsDir)) {
      error(`Assets directory missing: ${assetsDir}`);
    }
  }
}

function run() {
  checkPackageLock();
  checkInstalledDeps();
  checkRequirePaths();
  checkAssets();
  if (dryRun) {
    log('Dry-run complete.');
    if (hasError) log('Validation would fail.');
    else log('Validation would succeed.');
  } else {
    if (hasError) {
      log('Validation failed.');
      process.exit(1);
    } else {
      log('Validation successful.');
    }
  }
}

run();
