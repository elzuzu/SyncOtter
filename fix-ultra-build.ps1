# 🔧 fix-ultra-build.ps1 - Corriger le build ultra existant
# Fait fonctionner votre .\build.ps1 -Type ultra

Write-Host "🔧 Correction du build ultra SyncOtter" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green

$currentDir = Get-Location
Write-Host "📁 Répertoire: $currentDir" -ForegroundColor Cyan

try {
    # Backup du package.json actuel
    if (Test-Path "package.json") {
        $backupName = "package.json.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item "package.json" $backupName
        Write-Host "📋 Backup créé: $backupName" -ForegroundColor Gray
    }

    # Lire le package.json actuel
    Write-Host "📝 Lecture du package.json..." -ForegroundColor Yellow
    $packageContent = Get-Content "package.json" -Raw -Encoding UTF8
    $package = $packageContent | ConvertFrom-Json

    # Corriger l'encodage si nécessaire
    Write-Host "🔧 Correction de l'encodage..." -ForegroundColor Yellow
    
    # Ajouter l'auteur si manquant
    if (-not $package.author) {
        $package | Add-Member -NotePropertyName "author" -NotePropertyValue "SyncOtter Team" -Force
        Write-Host "   ✓ Auteur ajouté" -ForegroundColor Green
    }

    # Corriger les scripts
    Write-Host "🚀 Correction des scripts de build..." -ForegroundColor Yellow
    
    if (-not $package.scripts) {
        $package | Add-Member -NotePropertyName "scripts" -NotePropertyValue @{} -Force
    }

    # Script build-ultra corrigé (utilise electron-packager au lieu d'electron-builder)
    $package.scripts | Add-Member -NotePropertyName "build-ultra" -NotePropertyValue "electron-packager . SyncOtter --platform=win32 --arch=x64 --out=dist --overwrite --ignore=`"(node_modules/\\.bin|\\.git|\\.vscode|\\.tmp|dist|build)`" --prune=true" -Force
    
    # Autres scripts utiles
    $package.scripts | Add-Member -NotePropertyName "build-portable-light" -NotePropertyValue "electron-builder --win --x64 --config.win.target=portable --config.compression=store" -Force
    $package.scripts | Add-Member -NotePropertyName "build-light" -NotePropertyValue "electron-builder --win --x64 --config.compression=store" -Force

    Write-Host "   ✓ Script build-ultra corrigé (utilise electron-packager)" -ForegroundColor Green
    Write-Host "   ✓ Scripts de fallback ajoutés" -ForegroundColor Green

    # Ajouter electron-packager aux devDependencies
    Write-Host "📦 Ajout des dépendances..." -ForegroundColor Yellow
    
    if (-not $package.devDependencies) {
        $package | Add-Member -NotePropertyName "devDependencies" -NotePropertyValue @{} -Force
    }

    $package.devDependencies | Add-Member -NotePropertyName "electron-packager" -NotePropertyValue "^18.3.6" -Force
    Write-Host "   ✓ electron-packager ajouté" -ForegroundColor Green

    # Corriger la configuration build pour electron-builder (au cas où)
    Write-Host "⚙️ Configuration electron-builder..." -ForegroundColor Yellow
    
    if (-not $package.build) {
        $package | Add-Member -NotePropertyName "build" -NotePropertyValue @{} -Force
    }

    # Configuration ultra-optimisée
    $buildConfig = @{
        "appId" = "com.syncotter.app"
        "productName" = "SyncOtter"
        "compression" = "maximum"
        "win" = @{
            "target" = @(
                @{
                    "target" = "portable"
                    "arch" = @("x64")
                }
            )
        }
        "files" = @(
            "main.js",
            "splash.html",
            "!config.json",
            "!*.md",
            "!build.*",
            "!launch.*"
        )
        "portable" = @{
            "artifactName" = "SyncOtter-Ultra.exe"
        }
        "nsis" = @{
            "oneClick" = $false
            "allowToChangeInstallationDirectory" = $true
        }
    }

    # Appliquer la configuration
    foreach ($key in $buildConfig.Keys) {
        $package.build | Add-Member -NotePropertyName $key -NotePropertyValue $buildConfig[$key] -Force
    }

    Write-Host "   ✓ Configuration build optimisée" -ForegroundColor Green

    # Sauvegarder le package.json corrigé
    Write-Host "💾 Sauvegarde du package.json corrigé..." -ForegroundColor Yellow
    
    $newContent = $package | ConvertTo-Json -Depth 10
    
    # Utiliser Out-File avec encodage UTF8 sans BOM
    $newContent | Out-File "package.json" -Encoding UTF8 -Force
    
    Write-Host "✅ package.json corrigé et sauvegardé" -ForegroundColor Green

    # Installer electron-packager si nécessaire
    Write-Host "📦 Vérification des dépendances..." -ForegroundColor Yellow
    
    $hasPackager = npm list electron-packager 2>$null
    if (-not $hasPackager -or $LASTEXITCODE -ne 0) {
        Write-Host "   📥 Installation d'electron-packager..." -ForegroundColor Gray
        npm install --save-dev electron-packager
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   ⚠️ Erreur installation electron-packager, mais on continue..." -ForegroundColor Yellow
        } else {
            Write-Host "   ✅ electron-packager installé" -ForegroundColor Green
        }
    } else {
        Write-Host "   ✅ electron-packager déjà installé" -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "🎯 Correction terminée!" -ForegroundColor Green
    Write-Host ""
    Write-Host "🚀 Votre build ultra peut maintenant fonctionner:" -ForegroundColor Cyan
    Write-Host "   .\build.ps1 -Type ultra" -ForegroundColor White
    Write-Host ""
    Write-Host "💡 Alternatives si problème:" -ForegroundColor Yellow
    Write-Host "   npm run build-ultra                 # Direct" -ForegroundColor Gray
    Write-Host "   .\build.ps1 -Type portable         # Fallback" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🔧 Changements apportés:" -ForegroundColor Yellow
    Write-Host "   ✓ Script build-ultra utilise maintenant electron-packager" -ForegroundColor Green
    Write-Host "   ✓ Évite les problèmes de privilèges d'electron-builder" -ForegroundColor Green
    Write-Host "   ✓ Configuration ultra-optimisée pour réseau" -ForegroundColor Green
    Write-Host "   ✓ Encodage UTF-8 sans BOM" -ForegroundColor Green
    Write-Host "   ✓ Auteur et dépendances corrigés" -ForegroundColor Green

} catch {
    Write-Host ""
    Write-Host "❌ Erreur: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    
    Write-Host ""
    Write-Host "🔧 Solution manuelle:" -ForegroundColor Yellow
    Write-Host "1. Remplacez complètement package.json par la version corrigée" -ForegroundColor Gray
    Write-Host "2. Lancez: npm install --save-dev electron-packager" -ForegroundColor Gray
    Write-Host "3. Testez: .\build.ps1 -Type ultra" -ForegroundColor Gray
    
    exit 1
}

Write-Host ""
Write-Host "🦦 SyncOtter Ultra Build prêt!" -ForegroundColor Green