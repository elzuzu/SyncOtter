# Script de build ultra-robuste pour SyncOtter (inspiré du build-app.ps1 qui fonctionne)
param(
    [switch]$Clean = $true,
    [switch]$InstallDeps = $false,
    [switch]$Verbose = $false,
    [switch]$UsePackager = $true,  # Par défaut on évite electron-builder
    [switch]$UseBuilder = $false   # Option pour forcer electron-builder
)

# Couleurs pour les messages
$Red = [System.ConsoleColor]::Red
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow
$Cyan = [System.ConsoleColor]::Cyan
$Gray = [System.ConsoleColor]::Gray

function Write-ColorText($Text, $Color) {
    $currentColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Text
    $Host.UI.RawUI.ForegroundColor = $currentColor
}

# Obtenir le répertoire racine du projet
$projectRoot = $PSScriptRoot
Write-ColorText "🦦 SyncOtter Build Robuste" $Cyan
Write-ColorText "=========================" $Cyan
Write-ColorText "🚀 Répertoire du projet: $projectRoot" $Cyan

# Se déplacer dans le répertoire racine
Push-Location $projectRoot

try {
    # Étape 0: Vérifications préalables
    Write-ColorText "`n🔍 Vérifications préalables..." $Yellow
    
    # Vérifier Node.js
    try {
        $nodeVersion = node --version
        Write-ColorText "   ✓ Node.js: $nodeVersion" $Green
    } catch {
        throw "Node.js n'est pas installé ou n'est pas dans le PATH"
    }
    
    # Vérifier npm
    try {
        $npmVersion = npm --version
        Write-ColorText "   ✓ NPM: $npmVersion" $Green
    } catch {
        throw "NPM n'est pas disponible"
    }
    
    # Vérifier les fichiers essentiels
    $requiredFiles = @("main.js", "splash.html", "package.json")
    foreach ($file in $requiredFiles) {
        if (Test-Path $file) {
            Write-ColorText "   ✓ Fichier trouvé: $file" $Green
        } else {
            throw "Fichier critique manquant: $file"
        }
    }
    
    # Étape 1: Nettoyage
    if ($Clean) {
        Write-ColorText "`n🧹 Nettoyage complet..." $Yellow
        
        # Arrêter tous les processus Node/Electron
        Get-Process node*, electron* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Supprimer tous les dossiers de build
        @("out", "dist", "release-builds", "build") | ForEach-Object {
            if (Test-Path $_) {
                try {
                    Remove-Item -Path $_ -Recurse -Force -ErrorAction Stop
                    Write-ColorText "   ✓ Supprimé: $_" $Gray
                } catch {
                    Write-ColorText "   ⚠️ Impossible de supprimer: $_ (fichiers verrouillés?)" $Yellow
                }
            }
        }
        
        Write-ColorText "✅ Nettoyage terminé" $Green
    }
    
    # Étape 2: Installation des dépendances
    if ($InstallDeps -or -not (Test-Path "node_modules")) {
        Write-ColorText "`n📦 Installation des dépendances..." $Yellow
        
        if ($InstallDeps -and (Test-Path "node_modules")) {
            Write-ColorText "   🗑️ Suppression de node_modules..." $Yellow
            Remove-Item -Path "node_modules" -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        Write-ColorText "   📥 npm install..." $Gray
        npm install
        if ($LASTEXITCODE -ne 0) {
            throw "Échec de l'installation des dépendances (code: $LASTEXITCODE)"
        }
        Write-ColorText "✅ Dépendances installées" $Green
    }
    
    # Étape 3: Correction du package.json si nécessaire
    Write-ColorText "`n🔧 Vérification du package.json..." $Yellow
    
    $packageContent = Get-Content "package.json" -Raw
    $packageObj = $packageContent | ConvertFrom-Json
    
    $needsUpdate = $false
    
    # Vérifier l'auteur
    if (-not $packageObj.author) {
        $packageObj | Add-Member -NotePropertyName "author" -NotePropertyValue "SyncOtter Team" -Force
        $needsUpdate = $true
        Write-ColorText "   ✓ Auteur ajouté" $Green
    }
    
    # Vérifier les scripts de build
    if (-not $packageObj.scripts) {
        $packageObj | Add-Member -NotePropertyName "scripts" -NotePropertyValue @{} -Force
    }
    
    if (-not $packageObj.scripts."build-packager") {
        $packageObj.scripts | Add-Member -NotePropertyName "build-packager" -NotePropertyValue "electron-packager . SyncOtter --platform=win32 --arch=x64 --out=release-builds --overwrite" -Force
        $needsUpdate = $true
        Write-ColorText "   ✓ Script build-packager ajouté" $Green
    }
    
    # Sauvegarder si modifié
    if ($needsUpdate) {
        $backupName = "package.json.backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item "package.json" $backupName
        Write-ColorText "   📋 Backup créé: $backupName" $Gray
        
        $newContent = $packageObj | ConvertTo-Json -Depth 10
        $newContent | Out-File "package.json" -Encoding UTF8 -Force
        Write-ColorText "   ✓ package.json mis à jour" $Green
    }
    
    # Choix du mode de build
    if ($UsePackager -and -not $UseBuilder) {
        Write-ColorText "`n🔧 Mode Electron Packager (recommandé)..." $Cyan
        
        # Installer electron-packager si nécessaire
        $hasPackager = npm list @electron/packager 2>$null
        if (-not $hasPackager -or $LASTEXITCODE -ne 0) {
            Write-ColorText "   📦 Installation d'Electron Packager..." $Yellow
            npm install --save-dev @electron/packager
            if ($LASTEXITCODE -ne 0) {
                throw "Impossible d'installer @electron/packager"
            }
        }
        
        Write-ColorText "   🏗️ Build avec Electron Packager..." $Yellow
        
        # Créer le dossier de sortie
        New-Item -ItemType Directory -Path "release-builds" -Force | Out-Null
        
        # Paramètres de build
        $packagerArgs = @(
            ".",
            "SyncOtter",
            "--platform=win32",
            "--arch=x64", 
            "--out=release-builds",
            "--overwrite",
            "--ignore=`"(node_modules/\.bin|\.git|\.vscode|\.tmp|release-builds|dist|build)`""
        )
        
        npx electron-packager @packagerArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Échec du build avec electron-packager"
        }
        
    } else {
        Write-ColorText "`n🛠️ Mode Electron Builder..." $Cyan
        
        # Vérifier electron-builder
        $hasBuilder = npm list electron-builder 2>$null
        if (-not $hasBuilder -or $LASTEXITCODE -ne 0) {
            Write-ColorText "   📦 Installation d'Electron Builder..." $Yellow
            npm install --save-dev electron-builder
            if ($LASTEXITCODE -ne 0) {
                throw "Impossible d'installer electron-builder"
            }
        }
        
        Write-ColorText "   🏗️ Build avec Electron Builder..." $Yellow
        
        # Nettoyer le cache electron-builder pour éviter les problèmes de privilèges
        Remove-Item -Path "$env:LOCALAPPDATA\electron-builder\cache" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "$env:APPDATA\npm-cache\_prebuilds" -Recurse -Force -ErrorAction SilentlyContinue
        
        # Variables d'environnement pour désactiver le code signing
        $env:CSC_IDENTITY_AUTO_DISCOVERY = "false"
        $env:FORCE_COLOR = "0"
        
        if ($Verbose) { 
            $env:DEBUG = "electron-builder" 
        }
        
        # Tentative avec paramètres minimaux
        try {
            npx electron-builder --win --x64 --publish never --config.compression=store --config.win.target=portable
            if ($LASTEXITCODE -ne 0) {
                throw "Premier essai échoué"
            }
        } catch {
            Write-ColorText "   ⚠️ Premier essai échoué, tentative simplifiée..." $Yellow
            npx electron-builder --win --dir
            if ($LASTEXITCODE -ne 0) {
                throw "Tous les modes de build electron-builder ont échoué"
            }
        }
    }
    
    Write-ColorText "`n✅ Build terminé avec succès!" $Green
    
    # Recherche des fichiers générés
    $outputPaths = @("release-builds", "out", "dist")
    $foundFiles = @()
    
    foreach ($outputPath in $outputPaths) {
        if (Test-Path $outputPath) {
            $files = Get-ChildItem -Path $outputPath -Recurse | Where-Object { 
                $_.Extension -in @('.exe', '.zip', '.msi', '.nupkg') -or 
                ($_.PSIsContainer -and $_.Name -like '*SyncOtter*')
            }
            $foundFiles += $files
        }
    }
    
    if ($foundFiles.Count -gt 0) {
        Write-ColorText "`n📊 Résultats du build:" $Yellow
        foreach ($file in $foundFiles) {
            if ($file.PSIsContainer) {
                $folderSize = (Get-ChildItem -Path $file.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
                $size = [math]::Round($folderSize / 1MB, 2)
                Write-ColorText "   📁 $($file.Name)/ ($size MB)" $Green
                Write-ColorText "     $($file.FullName)" $Gray
                
                # Chercher l'exécutable dans le dossier
                $exeFiles = Get-ChildItem -Path $file.FullName -Recurse -Filter "*.exe"
                if ($exeFiles) {
                    foreach ($exe in $exeFiles) {
                        Write-ColorText "     🚀 $($exe.Name)" $Cyan
                    }
                }
            } else {
                $size = [math]::Round($file.Length / 1MB, 2)
                Write-ColorText "   ✓ $($file.Name) ($size MB)" $Green
                Write-ColorText "     $($file.FullName)" $Gray
            }
        }
        
        # Instructions d'utilisation
        Write-ColorText "`n📋 Instructions d'utilisation:" $Yellow
        Write-ColorText "1. Copiez le dossier/fichier généré où vous voulez" $Gray
        Write-ColorText "2. Créez un config.json à côté de l'exécutable avec vos paramètres" $Gray
        Write-ColorText "3. Lancez SyncOtter.exe" $Gray
        
    } else {
        Write-ColorText "`n⚠️ Aucun fichier exécutable trouvé dans les dossiers de sortie!" $Yellow
        Write-ColorText "Vérifiez les dossiers suivants manuellement:" $Gray
        foreach ($path in $outputPaths) {
            if (Test-Path $path) {
                Write-ColorText "   📁 $path" $Gray
            }
        }
    }

} catch {
    Write-ColorText "`n❌ Erreur: $_" $Red
    Write-ColorText "Stack trace:" $Red
    Write-ColorText $_.ScriptStackTrace $Gray
    
    Write-ColorText "`n🔧 Suggestions de dépannage:" $Yellow
    Write-ColorText "1. Essayez: .\syncotter-build-robust.ps1 -UsePackager" $Gray
    Write-ColorText "2. Ou bien: .\syncotter-build-robust.ps1 -UseBuilder" $Gray
    Write-ColorText "3. Ou encore: .\syncotter-build-robust.ps1 -InstallDeps -Clean" $Gray
    Write-ColorText "4. Vérifiez que main.js n'a pas d'erreurs de syntaxe" $Gray
    exit 1
} finally {
    Pop-Location
    # Nettoyer les variables d'environnement
    Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
    Remove-Item Env:CSC_IDENTITY_AUTO_DISCOVERY -ErrorAction SilentlyContinue
    Remove-Item Env:FORCE_COLOR -ErrorAction SilentlyContinue
}

Write-ColorText "`n✨ Script terminé!" $Green
Write-ColorText "💡 Par défaut utilise electron-packager (plus fiable)" $Cyan
Write-ColorText "💡 Utilisez -UseBuilder si vous préférez electron-builder" $Cyan