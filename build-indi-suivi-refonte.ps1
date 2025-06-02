# Script de build refondé pour Indi-Suivi - Inspiré de build-app-improved-upx.ps1 
param(
    [switch]$Clean = $true,
    [switch]$InstallDeps = $false,
    [switch]$Verbose = $false,
    [switch]$UseForge = $false,
    [switch]$UsePackager = $false,
    [switch]$SkipNativeDeps = $false,
    [switch]$SkipUPX = $false,
    [int]$UPXLevel = 9,
    [switch]$SkipOptimizations = $false
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

# Fonction UPX optimisée pour Indi-Suivi
function Invoke-UPXCompression {
    param(
        [string]$BuildPath = "release-builds",
        [int]$CompressionLevel = 9,
        [switch]$Verbose = $false
    )

    $upxPath = 'D:\tools\upx\upx.exe'

    if (-not (Test-Path $upxPath)) {
        Write-ColorText "ℹ️ UPX non trouvé à $upxPath - compression ignorée" $Gray
        return $false
    }

    try {
        $upxVersion = & $upxPath --version 2>&1 | Select-Object -First 1
        Write-ColorText "🗜️ Compression UPX ($upxVersion)..." $Yellow
    } catch {
        Write-ColorText "⚠️ UPX non fonctionnel - compression ignorée" $Yellow
        return $false
    }

    $compressed = 0
    $totalSavings = 0

    $searchPaths = @($BuildPath, "out", "dist")

    foreach ($searchPath in $searchPaths) {
        if (Test-Path $searchPath) {
            $executables = Get-ChildItem -Path $searchPath -Recurse -Filter "*.exe" |
                          Where-Object {
                              $_.Name -like "*Indi-Suivi*" -or
                              $_.Name -like "*indi-suivi*" -or
                              ($_.Directory.Name -eq "win-unpacked" -and $_.Name -eq "Indi-Suivi.exe")
                          }

            foreach ($exe in $executables) {
                $originalSize = $exe.Length
                $originalSizeMB = [math]::Round($originalSize / 1MB, 2)

                if ($originalSizeMB -lt 1 -or $originalSizeMB -gt 150) {
                    Write-ColorText "   ⏭️ $($exe.Name) ignoré (taille: $originalSizeMB MB)" $Gray
                    continue
                }

                Write-ColorText "   🗜️ Compression de $($exe.Name) ($originalSizeMB MB)..." $Cyan

                try {
                    $upxArgs = @(
                        "-$CompressionLevel",
                        "--best",
                        "--compress-icons=0",
                        "--strip-relocs=0",
                        $exe.FullName
                    )

                    if (-not $Verbose) { $upxArgs += "--quiet" }

                    & $upxPath @upxArgs 2>&1 | Out-Null

                    if ($LASTEXITCODE -eq 0) {
                        $newSize = (Get-Item $exe.FullName).Length
                        $newSizeMB = [math]::Round($newSize / 1MB, 2)
                        $reduction = [math]::Round((1 - $newSize / $originalSize) * 100, 1)
                        $totalSavings += $originalSize - $newSize
                        $compressed++

                        Write-ColorText "   ✅ $($exe.Name): $originalSizeMB MB → $newSizeMB MB (-$reduction%)" $Green
                    } else {
                        Write-ColorText "   ⚠️ Compression échouée pour $($exe.Name)" $Red
                    }
                } catch {
                    Write-ColorText "   ❌ Erreur compression $($exe.Name): $($_.Exception.Message)" $Red
                }
            }
        }
    }

    if ($compressed -gt 0) {
        $totalSavingsMB = [math]::Round($totalSavings / 1MB, 2)
        Write-ColorText "📊 Compression UPX terminée: $compressed fichier(s), économie: $totalSavingsMB MB" $Green
        return $true
    } else {
        Write-ColorText "ℹ️ Aucun fichier compressé" $Gray
        return $false
    }
}

# Optimisations spécifiques Indi-Suivi
function Invoke-IndiSuiviOptimizations {
    Write-ColorText "`n🗜️ Optimisations spécifiques Indi-Suivi..." $Yellow

    # Nettoyage des node_modules inutiles
    if (Test-Path "node_modules") {
        Write-ColorText "   🧹 Nettoyage node_modules..." $Gray
        
        # Supprimer les fichiers documentation
        Get-ChildItem "node_modules" -Recurse -Include @("*.md", "*.txt", "LICENSE*", "CHANGELOG*", "README*", "*.d.ts") -File | 
            Remove-Item -Force -ErrorAction SilentlyContinue
        
        # Supprimer les dossiers de test/docs
        Get-ChildItem "node_modules" -Recurse -Directory -Include @("test", "tests", "docs", "examples", "demo", "samples", "benchmark", ".github", "coverage", ".nyc_output") | 
            Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        
        Write-ColorText "   ✓ node_modules optimisé" $Green
    }

    # Optimisation des builds Vite
    if (Test-Path ".vite") {
        Get-ChildItem -Path ".vite" -Recurse -Include "*.map" | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-ColorText "   ✓ Source maps supprimées" $Gray
    }

    if (Test-Path "dist") {
        Get-ChildItem -Path "dist" -Recurse -Include @("*.md", "*.txt", "LICENSE*", "*.ts") -ErrorAction SilentlyContinue | 
            Remove-Item -Force -ErrorAction SilentlyContinue
        Write-ColorText "   ✓ Fichiers inutiles supprimés de dist" $Gray
    }
}

# Obtenir le répertoire racine du projet
$projectRoot = Split-Path -Parent $PSScriptRoot
Write-ColorText "🚀 Build Indi-Suivi - Projet: $projectRoot" $Cyan

# Se déplacer dans le répertoire racine
Push-Location $projectRoot

# Variables d'environnement pour optimisation
$env:NODE_ENV = "production"
$env:GENERATE_SOURCEMAP = "false"
$env:SKIP_PREFLIGHT_CHECK = "true"

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
        Write-ColorText "   ✓ npm: $npmVersion" $Green
    } catch {
        throw "npm n'est pas installé ou n'est pas dans le PATH"
    }
    
    # Vérifier l'icône
    $iconPath = Join-Path $projectRoot "src\assets\app-icon.ico"
    if (Test-Path $iconPath) {
        Write-ColorText "   ✓ Icône trouvée: $iconPath" $Green
    } else {
        Write-ColorText "   ⚠️ Icône manquante: $iconPath" $Red
        Write-ColorText "   Utilisation de l'icône par défaut Electron" $Yellow
    }
    
    # Vérifier les fichiers critiques
    $criticalFiles = @("package.json", "src\main.js")
    foreach ($file in $criticalFiles) {
        if (-not (Test-Path $file)) {
            throw "Fichier critique manquant: $file"
        }
        Write-ColorText "   ✓ Fichier critique trouvé: $file" $Green
    }
    
    # Étape 1: Nettoyage
    if ($Clean) {
        Write-ColorText "`n🧹 Nettoyage complet..." $Yellow
        
        # Arrêter tous les processus Node/Electron
        Get-Process node*, electron* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        # Supprimer tous les dossiers de build
        @("out", "dist", ".vite", "release-builds", "build", ".webpack", "node_modules/.cache") | ForEach-Object {
            if (Test-Path $_) {
                try {
                    Remove-Item -Path $_ -Recurse -Force -ErrorAction Stop
                    Write-ColorText "   ✓ Supprimé: $_" $Gray
                } catch {
                    Write-ColorText "   ⚠️ Impossible de supprimer: $_ (fichiers verrouillés?)" $Yellow
                }
            }
        }
        
        # Nettoyage du cache electron-builder
        $electronBuilderCache = "$env:LOCALAPPDATA\electron-builder\Cache"
        if (Test-Path $electronBuilderCache) {
            Remove-Item -Path $electronBuilderCache -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColorText "   ✓ Cache electron-builder nettoyé" $Gray
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
        
        # Installation des dépendances
        Write-ColorText "   📥 npm install..." $Gray
        npm install --include=dev --no-audit --prefer-offline
        if ($LASTEXITCODE -ne 0) {
            Write-ColorText "   ⚠️ npm install a échoué, tentative sans cache..." $Yellow
            npm cache clean --force
            npm install --include=dev --no-audit
            if ($LASTEXITCODE -ne 0) {
                throw "Échec de l'installation des dépendances (code: $LASTEXITCODE)"
            }
        }
        
        Write-ColorText "✅ Dépendances installées" $Green
    }
    
    # Étape 3: Build des composants
    Write-ColorText "`n🏗️ Build des composants..." $Yellow
    
    # Créer les dossiers de build nécessaires
    @(".vite", ".vite/build", "dist") | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-ColorText "   ✓ Créé: $_" $Gray
        }
    }
    
    # Build main.js
    Write-ColorText "   📝 Build main.js..." $Gray
    npx vite build --config vite.main.config.ts --mode production
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "   ❌ Échec du build main.js, utilisation du fallback" $Yellow
        if (Test-Path "src\main.js") {
            Copy-Item "src\main.js" ".vite\build\main.js" -Force
            Write-ColorText "   ✓ Fallback: main.js copié directement" $Yellow
        } else {
            throw "Impossible de construire main.js"
        }
    }
    
    # Build preload.js
    Write-ColorText "   📝 Build preload.js..." $Gray
    npx vite build --config vite.preload.config.ts --mode production
    if ($LASTEXITCODE -ne 0) {
        Write-ColorText "   ❌ Échec du build preload.js, utilisation du fallback" $Yellow
        if (Test-Path "src\preload.ts") {
            npx tsc src\preload.ts --outDir .vite\build --module commonjs --target es2020 --esModuleInterop --skipLibCheck
            if (-not (Test-Path ".vite\build\preload.js")) {
                throw "Impossible de construire preload.js"
            } else {
                Write-ColorText "   ✓ Fallback: preload.js compilé avec tsc" $Yellow
            }
        }
    }
    
    # Build renderer
    Write-ColorText "   📝 Build renderer..." $Gray
    npx vite build --config vite.config.js --mode production
    if ($LASTEXITCODE -ne 0) {
        throw "Échec du build renderer (React)"
    }
    
    # Vérifier les fichiers critiques après build
    $requiredFiles = @(
        ".vite/build/main.js",
        ".vite/build/preload.js",
        "dist/index.html"
    )
    foreach ($file in $requiredFiles) {
        if (-not (Test-Path $file)) {
            throw "Fichier critique manquant après build: $file"
        }
        Write-ColorText "   ✓ Vérifié: $file" $Green
    }
    
    # Étape 4: Rebuild des modules natifs (si pas ignoré)
    if (-not $SkipNativeDeps) {
        Write-ColorText "`n🔧 Rebuild des modules natifs..." $Yellow
        npx electron-rebuild -f -w better-sqlite3
        if ($LASTEXITCODE -ne 0) {
            Write-ColorText "   ⚠️ Rebuild des modules natifs échoué. Cela peut causer des problèmes d'exécution." $Yellow
        } else {
            Write-ColorText "   ✓ Modules natifs rebuilt" $Green
        }
    }
    
    # Étape 5: Optimisations (si pas ignorées)
    if (-not $SkipOptimizations) {
        Invoke-IndiSuiviOptimizations
    }
    
    # Étape 6: Construction de l'exécutable selon le mode choisi
    if ($UseForge) {
        Write-ColorText "`n🔧 Mode Electron Forge..." $Cyan
        if (-not (Test-Path "node_modules\@electron-forge")) {
            Write-ColorText "   📦 Installation d'Electron Forge..." $Yellow
            npm install --save-dev @electron-forge/cli @electron-forge/maker-squirrel @electron-forge/maker-deb @electron-forge/maker-rpm @electron-forge/maker-zip
            npx electron-forge import
        }
        npx electron-forge make
        $buildSuccess = $LASTEXITCODE -eq 0
    } elseif ($UsePackager) {
        Write-ColorText "`n🔧 Mode Electron Packager..." $Cyan
        if (-not (Test-Path "node_modules\@electron\packager")) {
            npm install --save-dev @electron/packager
        }
        npx electron-packager . "Indi-Suivi" --platform=win32 --arch=x64 --out=release-builds --overwrite --icon="src/assets/app-icon.ico"
        $buildSuccess = $LASTEXITCODE -eq 0
    } else {
        Write-ColorText "`n🛠️ Mode Electron Builder (défaut)..." $Cyan
        
        if ($Verbose) { $env:DEBUG = "electron-builder" }

        $builderArgs = @(
            "--win",
            "--publish", "never",
            "--config.compression=normal",
            "--config.nsis.oneClick=false",
            "--config.nsis.allowElevation=true"
        )

        npx electron-builder @builderArgs
        if ($LASTEXITCODE -ne 0) {
            Write-ColorText "   ⚠️ Electron-builder a échoué, nouvelle tentative..." $Yellow
            
            # Nettoyage du cache et nouvelle tentative
            $electronBuilderCache = "$env:LOCALAPPDATA\electron-builder\Cache"
            if (Test-Path $electronBuilderCache) {
                Remove-Item -Path $electronBuilderCache -Recurse -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
            }

            npx electron-builder --win --publish never --config.win.target=nsis
            if ($LASTEXITCODE -ne 0) {
                Write-ColorText "   ⚠️ Tentative finale avec --dir..." $Yellow
                npx electron-builder --win --dir
                if ($LASTEXITCODE -ne 0) {
                    throw "Tous les modes electron-builder ont échoué"
                }
            }
        }
        $buildSuccess = $true
    }
    
    if (-not $buildSuccess) {
        throw "La construction de l'exécutable a échoué"
    }
    
    Write-ColorText "`n✅ Build terminé avec succès!" $Green
    
    # Étape 7: Analyse des fichiers générés
    $outputPaths = @("release-builds", "out", "dist")
    $foundFiles = @()
    foreach ($outputPath in $outputPaths) {
        if (Test-Path $outputPath) {
            $files = Get-ChildItem -Path $outputPath -Recurse | Where-Object { $_.Extension -in @('.exe', '.zip', '.msi', '.nupkg', '.AppImage') }
            $foundFiles += $files
        }
    }

    # Étape 8: Compression UPX
    if (-not $SkipUPX) {
        Write-ColorText "`n🗜️ Compression UPX des exécutables..." $Yellow
        $upxSuccess = Invoke-UPXCompression -BuildPath "release-builds" -CompressionLevel $UPXLevel -Verbose:$Verbose
        if ($upxSuccess) {
            Write-ColorText "✅ Compression UPX terminée avec succès" $Green
            # Recharger les fichiers après compression
            $foundFiles = @()
            foreach ($outputPath in @("release-builds", "out", "dist")) {
                if (Test-Path $outputPath) {
                    $files = Get-ChildItem -Path $outputPath -Recurse | Where-Object { $_.Extension -in @('.exe', '.zip', '.msi', '.nupkg', '.AppImage') }
                    $foundFiles += $files
                }
            }
        } else {
            Write-ColorText "⚠️ Compression UPX ignorée ou échouée" $Yellow
        }
    } else {
        Write-ColorText "`n⏭️ Compression UPX ignorée (paramètre -SkipUPX)" $Gray
    }

    # Étape 9: Rapport final
    if ($foundFiles.Count -gt 0) {
        Write-ColorText "`n📊 Fichiers générés:" $Yellow
        foreach ($file in $foundFiles) {
            $size = [math]::Round($file.Length / 1MB, 2)
            Write-ColorText "   ✓ $($file.Name) ($size MB)" $Green
            Write-ColorText "     $($file.FullName)" $Gray
        }

        Write-ColorText "`n📊 Analyse de taille finale:" $Cyan
        foreach ($file in $foundFiles) {
            $sizeMB = [math]::Round($file.Length / 1MB, 2)
            $color = if ($sizeMB -gt 50) { $Red } elseif ($sizeMB -gt 30) { $Yellow } else { $Green }
            Write-ColorText "   📦 $($file.Name): $sizeMB MB" $color

            if ($sizeMB -le 40) {
                Write-ColorText "   ✅ Objectif < 40MB atteint!" $Green
            } elseif ($sizeMB -le 60) {
                Write-ColorText "   ⚠️ Acceptable mais peut être amélioré" $Yellow
            } else {
                Write-ColorText "   ❌ Trop volumineux - optimisations supplémentaires nécessaires" $Red
            }
        }
        
        # Exécutable principal
        $mainExe = $foundFiles | Where-Object { $_.Extension -eq '.exe' -and $_.Name -like '*Indi-Suivi*' } | Select-Object -First 1
        if ($mainExe) {
            Write-ColorText "`nℹ️ Exécutable principal: $($mainExe.FullName)" $Green
            Write-ColorText "   Taille finale: $([math]::Round($mainExe.Length / 1MB, 2)) MB" $Cyan
            Write-ColorText "   📂 Répertoire de sortie: release-builds/" $Cyan
        }
    } else {
        Write-ColorText "`n⚠️ Aucun fichier exécutable trouvé dans les dossiers de sortie!" $Yellow
    }
    
} catch {
    Write-ColorText "`n❌ Erreur: $_" $Red
    Write-ColorText "Stack trace:" $Red
    Write-ColorText $_.ScriptStackTrace $Gray
    Write-ColorText "`n🔧 Suggestions de dépannage:" $Yellow
    Write-ColorText "1. Essayez: .\build-indi-suivi-refonte.ps1 -UseForge" $Gray
    Write-ColorText "2. Ou bien: .\build-indi-suivi-refonte.ps1 -UsePackager" $Gray
    Write-ColorText "3. Ou encore: .\build-indi-suivi-refonte.ps1 -InstallDeps -Clean" $Gray
    Write-ColorText "4. Ou encore: .\build-indi-suivi-refonte.ps1 -SkipNativeDeps" $Gray
    Write-ColorText "5. Vérifiez les fichiers de configuration Vite" $Gray
    exit 1
} finally {
    Pop-Location
    Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
}

Write-ColorText "`n✨ Script terminé!" $Green
Write-ColorText "💡 Modes disponibles: Electron Builder (défaut), Electron Forge (-UseForge), Electron Packager (-UsePackager)" $Cyan
Write-ColorText "🎯 Objectif: Exécutable < 40MB avec compression UPX" $Cyan

