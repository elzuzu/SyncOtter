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
  const assets = ['src/assets/app-icon.ico', 'splash.html'];
  for (const asset of assets) {
    if (!fs.existsSync(asset)) {
      error(`Missing asset: ${asset}`);
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
