# Script de build pour SyncOtter
param(
    [switch]$Clean = $true,
    [switch]$InstallDeps = $false,
    [switch]$Verbose = $false,
    [switch]$UseForge = $false,
    [switch]$UsePackager = $false,
    [switch]$UltraPortable = $false
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

# Détection des privilèges administrateur
function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

# Nettoyage agressif du cache electron-builder
function Clean-ElectronBuilderCache {
    Write-ColorText "`n🧹 Nettoyage cache electron-builder..." $Yellow
    $paths = @(
        Join-Path $env:USERPROFILE ".cache\electron-builder",
        Join-Path $env:LOCALAPPDATA "electron-builder\cache"
    )
    foreach ($p in $paths) {
        if (Test-Path $p) {
            try {
                Remove-Item -Path $p -Recurse -Force -ErrorAction Stop
                Write-ColorText "   ✓ Supprimé: $p" $Gray
            } catch {
                Write-ColorText "   ⚠️ Impossible de supprimer: $p" $Yellow
            }
        }
    }
}

# Construction ultra-portable sans outils externes
function Build-UltraPortable {
    $outDir = Join-Path $projectRoot "ultra-portable"
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir | Out-Null
    $files = @(
        'main.js','package.json','splash.html','CacheManager.js','ErrorRecovery.js',
        'NetworkOptimizer.js','TransferManager.js','version-manager.js','config.json'
    )
    foreach ($f in $files) { if (Test-Path $f) { Copy-Item $f -Destination $outDir -Force } }
    foreach ($d in @('lib','logger','monitoring','src','node_modules')) {
        if (Test-Path $d) { Copy-Item $d -Destination (Join-Path $outDir $d) -Recurse -Force }
    }
    Write-ColorText "✅ Ultra-portable prêt dans $outDir" $Green
}

$projectRoot = $PSScriptRoot
Write-ColorText "🚀 Répertoire du projet: $projectRoot" $Cyan

Push-Location $projectRoot

try {
    # Vérifications préalables
    Write-ColorText "`n🔍 Vérifications préalables..." $Yellow
    try {
        $nodeVersion = node --version
        Write-ColorText "   ✓ Node.js: $nodeVersion" $Green
    } catch {
        throw "Node.js n'est pas installé ou n'est pas dans le PATH"
    }

    Clean-ElectronBuilderCache

    $iconPath = "src\assets\app-icon.ico"
    if (Test-Path $iconPath) {
        Write-ColorText "   ✓ Icône trouvée: $iconPath" $Green
    } else {
        Write-ColorText "   ⚠️ Icône manquante, création d'une icône par défaut..." $Yellow
        $assetsDir = "src\assets"
        if (-not (Test-Path $assetsDir)) {
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
        }
        Write-ColorText "   ⚠️ ATTENTION: Vous devez fournir une vraie icône .ico dans $iconPath" $Yellow
    }

    $utilsDir = "src\utils"
    $loggerPath = "$utilsDir\logger.js"
    if (-not (Test-Path $loggerPath)) {
        Write-ColorText "   📝 Création du module logger manquant..." $Yellow
        if (-not (Test-Path $utilsDir)) {
            New-Item -ItemType Directory -Path $utilsDir -Force | Out-Null
        }
        $loggerContent = @"
// Module logger simple
class Logger {
    static info(message) {
        console.log(`[INFO] ${new Date().toISOString()}: ${message}`);
    }
    static error(message) {
        console.error(`[ERROR] ${new Date().toISOString()}: ${message}`);
    }
    static warn(message) {
        console.warn(`[WARN] ${new Date().toISOString()}: ${message}`);
    }
    static debug(message) {
        console.log(`[DEBUG] ${new Date().toISOString()}: ${message}`);
    }
}
module.exports = { Logger };
"@
        Set-Content -Path $loggerPath -Value $loggerContent -Encoding UTF8
        Write-ColorText "   ✓ Module logger créé: $loggerPath" $Green
    }

    if ($Clean) {
        Write-ColorText "`n🧹 Nettoyage complet..." $Yellow
        Get-Process node*, electron* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        @("out", "dist", ".vite", "release-builds", "build", ".webpack") | ForEach-Object {
            if (Test-Path $_) {
                try {
                    Remove-Item -Path $_ -Recurse -Force -ErrorAction Stop
                    Write-ColorText "   ✓ Supprimé: $_" $Gray
                } catch {
                    Write-ColorText "   ⚠️ Impossible de supprimer: $_ (fichiers verrouillés?)" $Yellow
                }
            }
        }
        Get-ChildItem -Path . -Include @("*.exe", "*.zip", "*.AppImage", "*.dmg", "*.deb", "*.rpm") -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        Write-ColorText "✅ Nettoyage terminé" $Green
    }

    if ($InstallDeps -or -not (Test-Path "node_modules")) {
        Write-ColorText "`n📦 Installation des dépendances..." $Yellow
        if ($InstallDeps -and (Test-Path "node_modules")) {
            Write-ColorText "   🗑️ Suppression de node_modules..." $Yellow
            Remove-Item -Path "node_modules" -Recurse -Force -ErrorAction SilentlyContinue
        }
        npm cache clean --force | Out-Null
        Write-ColorText "   📥 npm install..." $Gray
        npm install
        if ($LASTEXITCODE -ne 0) {
            throw "Échec de l'installation des dépendances (code: $LASTEXITCODE)"
        }
        Write-ColorText "✅ Dépendances installées" $Green
    }

    Write-ColorText "`n📝 Compilation de preload.ts..." $Yellow
    if (-not (Test-Path "node_modules\typescript")) {
        Write-ColorText "   📦 Installation de TypeScript..." $Yellow
        npm install --save-dev typescript
        if ($LASTEXITCODE -ne 0) {
            throw "Impossible d'installer TypeScript"
        }
    }
    npx tsc src\preload.ts --outDir src --module commonjs --target es2020 --esModuleInterop --skipLibCheck
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path "src\preload.js")) {
        throw "Compilation de preload.ts echouée"
    }
    Write-ColorText "   ✓ preload.ts compilé" $Green

    if ($UseForge) {
        Write-ColorText "`n🔧 Mode Electron Forge..." $Cyan
        if (-not (Test-Path "node_modules\@electron-forge")) {
            npm install --save-dev @electron-forge/cli @electron-forge/maker-squirrel @electron-forge/maker-deb @electron-forge/maker-rpm @electron-forge/maker-zip
            npx electron-forge import
        }
        npx electron-forge make
    } elseif ($UsePackager) {
        Write-ColorText "`n🔧 Mode Electron Packager..." $Cyan
        if (-not (Test-Path "node_modules\@electron\packager")) {
            npm install --save-dev @electron/packager
        }
        npx electron-packager . "SyncOtter" --platform=win32 --arch=x64 --out=release-builds --overwrite --icon="src/assets/app-icon.ico"
    } elseif ($UltraPortable) {
        Write-ColorText "`n📦 Mode Ultra-Portable..." $Cyan
        Build-UltraPortable
    } else {
        Write-ColorText "`n🛠️ Mode Electron Builder (défaut)..." $Cyan
        $isAdmin = Test-IsAdmin
        $builderArgs = @(
            "--win",
            "--publish", "never",
            "--config.win.sign=null",
            "--config.compression=normal",
            "--config.nsis.oneClick=false",
            "--config.nsis.allowElevation=true"
        )
        if (-not $isAdmin) {
            $builderArgs += "--dir"
            Write-ColorText "   ⚠️ Exécution sans privilèges admin - build en mode dossier" $Yellow
        } else {
            Write-ColorText "   ✓ Privilèges admin détectés" $Green
        }
        if ($Verbose) { $env:DEBUG = "electron-builder" }
        npx electron-builder @builderArgs
        if ($LASTEXITCODE -ne 0) {
            Write-ColorText "   ⚠️ Electron-builder a échoué, fallback electron-packager..." $Yellow
            if (-not (Test-Path "node_modules\@electron\packager")) { npm install --save-dev @electron/packager }
            npx electron-packager . "SyncOtter" --platform=win32 --arch=x64 --out=release-builds --overwrite --icon="src/assets/app-icon.ico"
            if ($LASTEXITCODE -ne 0) { throw "Tous les modes de build ont échoué" }
        }
    }

    Write-ColorText "`n✅ Build terminé avec succès!" $Green

} catch {
    Write-ColorText "`n❌ Erreur: $_" $Red
    Write-ColorText "Stack trace:" $Red
    Write-ColorText $_.ScriptStackTrace $Gray
    exit 1
} finally {
    Pop-Location
    Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
}

Write-ColorText "`n✨ Script terminé!" $Green
Write-ColorText "💡 Utilisez -UseForge, -UsePackager ou -UltraPortable si electron-builder pose problème" $Cyan
