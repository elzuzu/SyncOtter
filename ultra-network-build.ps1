# 🦦 SyncOtter Ultra-Network Build
# Version ultra-légère optimisée pour lancement depuis partage réseau

param(
    [switch]$Clean = $true,
    [string]$NetworkPath = "",
    [switch]$TestLocal = $false
)

Write-Host "🦦 SyncOtter Ultra-Network Build" -ForegroundColor Green
Write-Host "================================" -ForegroundColor Green
Write-Host "🌐 Version optimisée pour partage réseau" -ForegroundColor Cyan

$currentDir = $PSScriptRoot

try {
    # Étape 1: Nettoyage
    if ($Clean) {
        Write-Host "`n🧹 Nettoyage..." -ForegroundColor Yellow
        @("dist", "release-builds", "ultra-network") | ForEach-Object {
            if (Test-Path $_) {
                Remove-Item -Recurse -Force $_ -ErrorAction SilentlyContinue
                Write-Host "   ✓ Supprimé: $_" -ForegroundColor Gray
            }
        }
    }

    # Étape 2: Créer la version ultra-network
    $ultraDir = "ultra-network"
    Write-Host "`n📦 Création version ultra-réseau..." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $ultraDir -Force | Out-Null

    # Copier seulement les fichiers essentiels
    Write-Host "📋 Copie des fichiers ultra-essentiels..." -ForegroundColor Gray
    $essentialFiles = @{
        "main.js" = "Fichier principal Electron"
        "splash.html" = "Interface utilisateur"
    }

    foreach ($file in $essentialFiles.Keys) {
        if (Test-Path $file) {
            Copy-Item $file $ultraDir -Force
            Write-Host "   ✓ $file ($($essentialFiles[$file]))" -ForegroundColor Green
        } else {
            throw "Fichier critique manquant: $file"
        }
    }

    # Créer un package.json ultra-minimal
    Write-Host "📝 Package.json ultra-minimal..." -ForegroundColor Gray
    $ultraPackage = @{
        "name" = "syncotter-ultra"
        "version" = "1.0.0"
        "main" = "main.js"
        "author" = "SyncOtter Team"
        "scripts" = @{
            "start" = "electron ."
        }
        "dependencies" = @{
            "electron" = "^28.0.0"
        }
    }

    $ultraPackage | ConvertTo-Json -Depth 5 | Out-File "$ultraDir\package.json" -Encoding UTF8 -Force
    Write-Host "   ✓ package.json ultra-minimal créé" -ForegroundColor Green

    # Créer le lanceur réseau ultra-optimisé
    Write-Host "🚀 Lanceur réseau ultra-optimisé..." -ForegroundColor Gray
    $networkLauncher = @"
@echo off
title SyncOtter Ultra-Network
echo 🦦 SyncOtter Ultra-Network
echo =========================
echo 🌐 Version optimisée pour partage réseau
echo.

REM Variables de performance réseau
set NODE_OPTIONS=--max-old-space-size=512
set ELECTRON_DISABLE_SECURITY_WARNINGS=true
set ELECTRON_IS_DEV=0

REM Détecter si on est sur le réseau
set "SCRIPT_DIR=%~dp0"
echo 📍 Localisation: %SCRIPT_DIR%

REM Vérification rapide de Node.js
node --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Node.js requis! Installez Node.js 20 LTS
    pause
    exit /b 1
)

REM Gestion du cache local pour performance réseau
set "CACHE_DIR=%LOCALAPPDATA%\SyncOtter-Cache"
set "CONFIG_CACHE=%CACHE_DIR%\config.json"

REM Créer cache local si nécessaire
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"

REM Copier config en cache local pour vitesse
if exist "%SCRIPT_DIR%config.json" (
    if not exist "%CONFIG_CACHE%" (
        echo 📥 Mise en cache config réseau...
        copy "%SCRIPT_DIR%config.json" "%CONFIG_CACHE%" >nul
    ) else (
        REM Vérifier si config réseau plus récent
        for %%F in ("%SCRIPT_DIR%config.json") do set "NET_DATE=%%~tF"
        for %%F in ("%CONFIG_CACHE%") do set "CACHE_DATE=%%~tF"
        if "%NET_DATE%" NEQ "%CACHE_DATE%" (
            echo 🔄 Mise à jour cache config...
            copy "%SCRIPT_DIR%config.json" "%CONFIG_CACHE%" >nul
        )
    )
    echo ✅ Config en cache local pour performance
) else (
    echo ⚠️  Aucun config.json sur le réseau
    if not exist "%CONFIG_CACHE%" (
        echo 💡 Création config d'exemple en cache local...
        echo {> "%CONFIG_CACHE%"
        echo   "sourceDirectory": "C:\\Source",>> "%CONFIG_CACHE%"
        echo   "targetDirectory": "C:\\Target",>> "%CONFIG_CACHE%"
        echo   "executeAfterSync": "C:\\Target\\app.exe",>> "%CONFIG_CACHE%"
        echo   "appName": "Application Réseau">> "%CONFIG_CACHE%"
        echo }>> "%CONFIG_CACHE%"
        echo ✅ Config d'exemple créé en: %CONFIG_CACHE%
        echo 💡 Éditez ce fichier pour personnaliser
    )
)

REM Installation rapide des dépendances en cache
set "NODE_MODULES_CACHE=%CACHE_DIR%\node_modules"
if not exist "%NODE_MODULES_CACHE%" (
    echo 📦 Installation deps en cache local...
    pushd "%CACHE_DIR%"
    
    REM Copier package.json minimal
    copy "%SCRIPT_DIR%package.json" . >nul
    
    REM Install en mode production seulement
    npm install --production --silent --no-audit --no-fund
    if errorlevel 1 (
        echo ❌ Échec installation cache
        popd
        pause
        exit /b 1
    )
    popd
    echo ✅ Dépendances cachées localement
) else (
    echo ✅ Utilisation cache deps existant
)

REM Copier les fichiers de l'app en cache pour vitesse
echo 📥 Copie app en cache pour performance...
copy "%SCRIPT_DIR%main.js" "%CACHE_DIR%\" >nul 2>&1
copy "%SCRIPT_DIR%splash.html" "%CACHE_DIR%\" >nul 2>&1

REM Lancement depuis cache local = ULTRA RAPIDE
echo 🚀 Lancement ultra-rapide depuis cache local...
echo 💡 App: %CACHE_DIR%
echo 💡 Config: %CONFIG_CACHE%
echo.

pushd "%CACHE_DIR%"
npm start
set "EXIT_CODE=%ERRORLEVEL%"
popd

if %EXIT_CODE% neq 0 (
    echo.
    echo ❌ Erreur au lancement (code: %EXIT_CODE%)
    echo 💡 Essayez de supprimer: %CACHE_DIR%
    pause
) else (
    echo.
    echo ✅ SyncOtter fermé normalement
)

REM Nettoyer variables
set NODE_OPTIONS=
set ELECTRON_DISABLE_SECURITY_WARNINGS=
set ELECTRON_IS_DEV=
"@

    $networkLauncher | Out-File "$ultraDir\SyncOtter-Network.bat" -Encoding ascii -Force
    Write-Host "   ✓ SyncOtter-Network.bat créé" -ForegroundColor Green

    # Créer un config d'exemple pour le réseau
    Write-Host "📝 Config d'exemple réseau..." -ForegroundColor Gray
    $networkConfig = @{
        "sourceDirectory" = "\\serveur\partage\source"
        "targetDirectory" = "C:\Applications\MonApp"
        "excludeDirectories" = @(".git", "node_modules", ".tmp")
        "excludePatterns" = @("*.log", "*.tmp", "thumbs.db")
        "executeAfterSync" = "C:\Applications\MonApp\app.exe"
        "appName" = "Application Réseau"
        "appDescription" = "Synchronisation depuis partage réseau"
        "parallelCopies" = 8
        "networkOptimized" = $true
        "cacheEnabled" = $true
    }

    $networkConfig | ConvertTo-Json -Depth 5 | Out-File "$ultraDir\config.example.json" -Encoding UTF8 -Force
    Write-Host "   ✓ config.example.json créé" -ForegroundColor Green

    # Créer les instructions réseau
    $networkInstructions = @"
# 🦦 SyncOtter Ultra-Network - Instructions

## 🌐 Version Optimisée Partage Réseau

### Déploiement:
1. Copiez le dossier ultra-network sur votre partage réseau
2. Renommez config.example.json en config.json  
3. Modifiez config.json avec vos chemins réseau
4. Les utilisateurs lancent SyncOtter-Network.bat depuis le réseau

### Optimisations Réseau:
✅ Cache local automatique des dépendances
✅ Cache local de l'application pour vitesse
✅ Configuration mise en cache intelligemment  
✅ Lancement ultra-rapide après premier démarrage
✅ Gestion automatique des mises à jour config

### Performance:
- Premier lancement: ~30-60 secondes (installation cache)
- Lancements suivants: ~2-5 secondes (depuis cache)
- Cache local: %LOCALAPPDATA%\SyncOtter-Cache

### Avantages:
🚀 Ultra-rapide après mise en cache
📦 Seulement ~50KB sur le réseau (sans node_modules)
🔄 Mise à jour automatique du cache si config change
🌐 Partageable sur tout le réseau d'entreprise
💾 Cache intelligent par utilisateur

### Utilisation:
1. Double-clic sur SyncOtter-Network.bat depuis le réseau
2. Première fois: Installation automatique en cache local
3. Fois suivantes: Lancement immédiat depuis cache
4. Configuration modifiable en réseau, cache mis à jour auto

### Dépannage:
- Si problème: Supprimer %LOCALAPPDATA%\SyncOtter-Cache
- Cache sera recréé au prochain lancement
- Chaque utilisateur a son propre cache local
"@

    $networkInstructions | Out-File "$ultraDir\README-NETWORK.txt" -Encoding UTF8 -Force
    Write-Host "   ✓ README-NETWORK.txt créé" -ForegroundColor Green

    # Script de déploiement réseau
    Write-Host "🌐 Script de déploiement réseau..." -ForegroundColor Gray
    $deployScript = @"
# 🌐 deploy-to-network.ps1 - Déploiement vers partage réseau
param(
    [Parameter(Mandatory=`$true)]
    [string]`$NetworkPath,
    [string]`$ConfigSource = "",
    [string]`$AppName = "SyncOtter"
)

Write-Host "🌐 Déploiement SyncOtter vers réseau" -ForegroundColor Green
Write-Host "NetworkPath: `$NetworkPath" -ForegroundColor Cyan

if (-not (Test-Path `$NetworkPath)) {
    Write-Host "❌ Chemin réseau inaccessible: `$NetworkPath" -ForegroundColor Red
    exit 1
}

`$targetDir = Join-Path `$NetworkPath `$AppName
Write-Host "📁 Répertoire cible: `$targetDir" -ForegroundColor Cyan

# Créer le répertoire cible
if (-not (Test-Path `$targetDir)) {
    New-Item -ItemType Directory -Path `$targetDir -Force | Out-Null
    Write-Host "✅ Répertoire créé: `$targetDir" -ForegroundColor Green
}

# Copier tous les fichiers ultra-network
Write-Host "📦 Copie des fichiers..." -ForegroundColor Yellow
Copy-Item "$ultraDir\*" `$targetDir -Recurse -Force
Write-Host "✅ Fichiers copiés" -ForegroundColor Green

# Copier config personnalisé si fourni
if (`$ConfigSource -and (Test-Path `$ConfigSource)) {
    Copy-Item `$ConfigSource "`$targetDir\config.json" -Force
    Write-Host "✅ Configuration personnalisée copiée" -ForegroundColor Green
} else {
    Write-Host "💡 Renommez config.example.json en config.json et modifiez-le" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎯 Déploiement terminé!" -ForegroundColor Green
Write-Host "📍 Emplacement réseau: `$targetDir\SyncOtter-Network.bat" -ForegroundColor Cyan
Write-Host "💡 Les utilisateurs peuvent maintenant lancer depuis le réseau" -ForegroundColor Yellow
"@

    $deployScript | Out-File "$ultraDir\deploy-to-network.ps1" -Encoding UTF8 -Force
    Write-Host "   ✓ deploy-to-network.ps1 créé" -ForegroundColor Green

    # Calculer la taille ultra-légère
    $totalSize = (Get-ChildItem $ultraDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $sizeKB = [math]::Round($totalSize / 1KB, 1)

    Write-Host "`n✅ Version Ultra-Network créée!" -ForegroundColor Green
    Write-Host "📏 Taille sur réseau: $sizeKB KB (ultra-léger!)" -ForegroundColor Cyan
    Write-Host "📁 Emplacement: $ultraDir" -ForegroundColor Cyan

    Write-Host "`n🌐 Avantages de cette version:" -ForegroundColor Yellow
    Write-Host "   🚀 Lancement ultra-rapide depuis réseau" -ForegroundColor Green
    Write-Host "   💾 Cache local automatique" -ForegroundColor Green  
    Write-Host "   📦 Seulement $sizeKB KB sur partage réseau" -ForegroundColor Green
    Write-Host "   🔄 Mise à jour config automatique" -ForegroundColor Green
    Write-Host "   👥 Multi-utilisateurs avec cache individuel" -ForegroundColor Green

    # Test local si demandé
    if ($TestLocal) {
        Write-Host "`n🧪 Test local..." -ForegroundColor Yellow
        Push-Location $ultraDir
        .\SyncOtter-Network.bat
        Pop-Location
    }

    # Instructions de déploiement
    Write-Host "`n📋 Déploiement sur réseau:" -ForegroundColor Yellow
    Write-Host "   1. Copier le dossier '$ultraDir' sur votre partage réseau" -ForegroundColor Gray
    Write-Host "   2. Renommer config.example.json en config.json" -ForegroundColor Gray
    Write-Host "   3. Modifier config.json avec vos chemins" -ForegroundColor Gray
    Write-Host "   4. Utilisateurs lancent SyncOtter-Network.bat depuis réseau" -ForegroundColor Gray

    Write-Host "`n🚀 Déploiement automatique:" -ForegroundColor Yellow
    Write-Host "   .\ultra-network\deploy-to-network.ps1 -NetworkPath '\\serveur\partage' -AppName 'SyncOtter'" -ForegroundColor White

} catch {
    Write-Host "`n❌ Erreur: $_" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
    exit 1
}

Write-Host "`n🦦 SyncOtter Ultra-Network prêt!" -ForegroundColor Green
Write-Host "💡 Optimisé pour partage réseau avec cache local intelligent" -ForegroundColor Cyan