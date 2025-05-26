# 🎯 working-solution-fixed.ps1 - Solution corrigée
# Correction des problèmes de chemins

Write-Host "🎯 Solution SyncOtter CORRIGÉE" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green

# Obtenir le répertoire de travail actuel
$currentDir = Get-Location
Write-Host "📁 Répertoire de travail: $currentDir" -ForegroundColor Cyan

Write-Host ""
Write-Host "Option 1: Test immédiat (mode développement)" -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan

Write-Host "🧪 Test en mode développement..." -ForegroundColor Yellow
Write-Host "💡 SyncOtter va se lancer dans une nouvelle fenêtre..." -ForegroundColor Gray

# Lancer en arrière-plan
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$currentDir'; npm start" -WindowStyle Normal

Write-Host "✅ SyncOtter lancé en mode développement!" -ForegroundColor Green

Start-Sleep 2

Write-Host ""
Write-Host "Option 2: Package portable manuel" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Créer un package portable simple - chemins relatifs corrects
$portableDir = Join-Path $currentDir "dist\SyncOtter-Portable"

Write-Host "📦 Création du package portable dans: $portableDir" -ForegroundColor Yellow

# Nettoyer et créer avec chemins absolus corrects
$distDir = Join-Path $currentDir "dist"
if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir -ErrorAction SilentlyContinue
}

Write-Host "📁 Création des répertoires..." -ForegroundColor Gray
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
New-Item -ItemType Directory -Path $portableDir -Force | Out-Null

Write-Host "📋 Copie des fichiers essentiels..." -ForegroundColor Gray
# Vérifier et copier les fichiers essentiels
$filesToCopy = @("main.js", "splash.html")
foreach ($file in $filesToCopy) {
    if (Test-Path $file) {
        Copy-Item $file $portableDir -Force
        Write-Host "   ✓ Copié: $file" -ForegroundColor Green
    } else {
        Write-Host "   ⚠️ Manquant: $file" -ForegroundColor Yellow
    }
}

# Créer un package.json minimal pour le portable
Write-Host "📝 Création du package.json..." -ForegroundColor Gray
$portablePackageJson = @{
    "name" = "syncotter"
    "version" = "1.0.0"
    "main" = "main.js"
    "author" = "SyncOtter Team"
    "scripts" = @{
        "start" = "electron ."
    }
    "dependencies" = @{
        "electron" = "^28.0.0"
        "fs-extra" = "^11.2.0"
    }
}

$jsonString = $portablePackageJson | ConvertTo-Json -Depth 5
$packageJsonPath = Join-Path $portableDir "package.json"

# Utiliser Out-File avec encoding UTF8 (plus fiable)
$jsonString | Out-File -FilePath $packageJsonPath -Encoding UTF8 -Force
Write-Host "   ✓ package.json créé" -ForegroundColor Green

# Créer un script de lancement amélioré
Write-Host "📝 Création du lanceur..." -ForegroundColor Gray
$launchScript = @"
@echo off
title SyncOtter - Lanceur Portable
echo 🦦 SyncOtter - Version Portable
echo ===============================
echo.

REM Vérifier Node.js
node --version >nul 2>&1
if errorlevel 1 (
    echo ❌ Node.js requis!
    echo.
    echo 💡 Installez Node.js 20 LTS depuis: https://nodejs.org
    echo.
    pause
    exit /b 1
)

echo ✅ Node.js détecté: 
node --version

REM Installer les dépendances si nécessaire
if not exist node_modules (
    echo 📦 Installation des dépendances...
    npm install --production --silent
    if errorlevel 1 (
        echo ❌ Échec de l'installation
        pause
        exit /b 1
    )
    echo ✅ Dépendances installées
    echo.
)

REM Vérifier le config.json
if not exist config.json (
    echo ⚠️  config.json manquant
    echo.
    echo 💡 Création d'un config.json d'exemple...
    echo {> config.json
    echo   "sourceDirectory": "C:\\Source",>> config.json
    echo   "targetDirectory": "C:\\Target",>> config.json
    echo   "executeAfterSync": "C:\\Target\\app.exe",>> config.json
    echo   "appName": "Mon Application">> config.json
    echo }>> config.json
    echo.
    echo ✅ config.json créé! Modifiez-le selon vos besoins.
    echo.
)

echo 🚀 Lancement de SyncOtter...
echo.
npm start

if errorlevel 1 (
    echo.
    echo ❌ Erreur au lancement
    pause
) else (
    echo.
    echo ✅ SyncOtter fermé normalement
)

pause
"@

$launchScriptPath = Join-Path $portableDir "SyncOtter.bat"
$launchScript | Out-File -FilePath $launchScriptPath -Encoding ascii -Force
Write-Host "   ✓ SyncOtter.bat créé" -ForegroundColor Green

# Créer un exemple de config
Write-Host "📝 Création du config d'exemple..." -ForegroundColor Gray
$exampleConfig = @{
    "sourceDirectory" = "C:\\Source"
    "targetDirectory" = "C:\\Target"
    "excludeDirectories" = @(".git", "node_modules", ".vs")
    "excludePatterns" = @("*.tmp", "*.log")
    "executeAfterSync" = "C:\\Target\\app.exe"
    "appName" = "Mon Application"
    "appDescription" = "Synchronisation et lancement automatique"
    "parallelCopies" = 4
}

$configJson = $exampleConfig | ConvertTo-Json -Depth 5
$configExamplePath = Join-Path $portableDir "config.example.json"
$configJson | Out-File -FilePath $configExamplePath -Encoding UTF8 -Force
Write-Host "   ✓ config.example.json créé" -ForegroundColor Green

# Instructions
Write-Host "📝 Création des instructions..." -ForegroundColor Gray
$instructions = @"
# 🦦 SyncOtter - Instructions d'utilisation

## Installation rapide:
1. Installez Node.js 20 LTS (https://nodejs.org)
2. Double-cliquez sur SyncOtter.bat
3. Modifiez config.json selon vos besoins

## Configuration:
Le fichier config.json sera créé automatiquement au premier lancement.
Éditez-le pour définir:
- sourceDirectory: Répertoire source à synchroniser
- targetDirectory: Répertoire destination  
- executeAfterSync: Application à lancer après la sync

## Exemple d'utilisation:
1. Première utilisation: Double-clic sur SyncOtter.bat
2. Éditer config.json avec vos chemins
3. Relancer SyncOtter.bat

## Support:
- Cette version nécessite Node.js installé sur le système
- Avantage: Fonctionne sur n'importe quel Windows avec Node.js
- Aucun problème de privilèges administrateur

## Dépannage:
- Si erreur "Node.js requis": Installez Node.js 20 LTS
- Si erreur au démarrage: Vérifiez les chemins dans config.json
- Logs visibles dans la console qui s'ouvre
"@

$instructionsPath = Join-Path $portableDir "README.txt"
$instructions | Out-File -FilePath $instructionsPath -Encoding UTF8 -Force
Write-Host "   ✓ README.txt créé" -ForegroundColor Green

Write-Host "✅ Package portable créé avec succès!" -ForegroundColor Green

# Calculer la taille
if (Test-Path $portableDir) {
    $totalSize = (Get-ChildItem $portableDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $sizeMB = [math]::Round($totalSize / 1MB, 2)
    Write-Host "📏 Taille du package: $sizeMB MB" -ForegroundColor Cyan
} else {
    Write-Host "❌ Erreur: Le répertoire portable n'a pas été créé" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "🎯 Votre SyncOtter est prêt!" -ForegroundColor Green
Write-Host ""
Write-Host "📁 Package portable: $portableDir" -ForegroundColor Cyan
Write-Host "🚀 Lancement: SyncOtter.bat" -ForegroundColor Cyan
Write-Host ""
Write-Host "💡 Ce package fonctionne sur tout Windows avec Node.js" -ForegroundColor Yellow
Write-Host "💡 Partageable et portable sans problème de privilèges" -ForegroundColor Yellow

Write-Host ""
Write-Host "🧪 Test immédiat:" -ForegroundColor Yellow
Write-Host "   cd `"$portableDir`"" -ForegroundColor White
Write-Host "   .\SyncOtter.bat" -ForegroundColor White

Write-Host ""
Write-Host "📋 Contenu du package:" -ForegroundColor Cyan
Get-ChildItem $portableDir | ForEach-Object {
    Write-Host "   📄 $($_.Name)" -ForegroundColor Gray
}