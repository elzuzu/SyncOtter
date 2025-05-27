# Clean install script for SyncOtter
Remove-Item -Recurse -Force node_modules, 'package-lock.json' -ErrorAction SilentlyContinue
npm cache clean --force
npm install --legacy-peer-deps
