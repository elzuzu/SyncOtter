# Clean install script for SyncOtter
if (Test-Path "node_modules") { Remove-Item -Recurse -Force node_modules }
if (Test-Path "package-lock.json") { Remove-Item -Force package-lock.json }
npm cache clean --force
npm install --legacy-peer-deps
