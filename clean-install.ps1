# Clean install script for SyncOtter with better error handling
Write-Host "🧹 Nettoyage complet..." -ForegroundColor Yellow

# Stop any running processes
Get-Process node*,electron*,SyncOtter* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# Remove directories with retry
$dirsToRemove = @("node_modules", "dist", "build", "out", "release-builds")
foreach ($dir in $dirsToRemove) {
    if (Test-Path $dir) {
        Write-Host "Suppression de $dir..." -ForegroundColor Gray
        for ($i = 0; $i -lt 3; $i++) {
            try {
                Remove-Item -Recurse -Force $dir -ErrorAction Stop
                break
            } catch {
                Start-Sleep -Seconds 1
                if ($i -eq 2) { Write-Warning "Impossible de supprimer $dir" }
            }
        }
    }
}

# Remove lock files
@( "package-lock.json", "yarn.lock" ) | Where-Object { Test-Path $_ } | Remove-Item -Force

Write-Host "🗑️ Cache npm..." -ForegroundColor Gray
npm cache clean --force

Write-Host "📦 Installation des dépendances..." -ForegroundColor Green
npm install --legacy-peer-deps

Write-Host "✅ Nettoyage terminé" -ForegroundColor Green
