# Script de build pour SyncOtter
param(
    [switch]$Clean = $true,
    [switch]$InstallDeps = $false,
    [switch]$Verbose = $false,
    [switch]$UseForge = $false,
    [switch]$UsePackager = $false,
    [switch]$Recovery = $false
)

# Couleurs pour les messages
$Red = [System.ConsoleColor]::Red
$Green = [System.ConsoleColor]::Green
$Yellow = [System.ConsoleColor]::Yellow
$Cyan = [System.ConsoleColor]::Cyan
$Gray = [System.ConsoleColor]::Gray

# Fichier de log
$logDir = Join-Path $PSScriptRoot 'logs'
if(-not (Test-Path $logDir)){ New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$logFile = Join-Path $logDir 'build-app.log'

$LevelColor = @{ INFO=$Gray; SUCCESS=$Green; WARN=$Yellow; ERROR=$Red }

function Write-Log {
    param([string]$Level, [string]$Message, [string]$Code = '')
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts][$Level][$Code] $Message"
    $color = $LevelColor[$Level]
    $currentColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $color
    Write-Host $line
    $Host.UI.RawUI.ForegroundColor = $currentColor
    Add-Content -Path $logFile -Value $line
}

function Invoke-WithRetry {
    param([ScriptBlock]$Action, [string]$Name)
    $attempt = 0
    while($attempt -lt 3){
        try{
            & $Action
            return
        }catch{
            $attempt++
            Write-Log 'WARN' "Echec $Name tentative $attempt" 'RETRY'
            Stop-BlockingProcesses
            if($attempt -ge 3){ throw }
            Start-Sleep -Seconds 1
        }
    }
}

function Stop-BlockingProcesses {
    Get-Process node*,electron* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Write-ColorText($Text, $Color) {
    $currentColor = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $Color
    Write-Host $Text
    $Host.UI.RawUI.ForegroundColor = $currentColor
    Add-Content -Path $logFile -Value "[console] $Text"
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


$projectRoot = $PSScriptRoot
Write-ColorText "🚀 Répertoire du projet: $projectRoot" $Cyan

# sauvegarde éventuelle pour recovery
$backupPath = Join-Path $projectRoot 'build_backup'
if(Test-Path 'dist'){
    Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue
    Copy-Item 'dist' $backupPath -Recurse -Force -ErrorAction SilentlyContinue
}

Push-Location $projectRoot

try {
    # Vérifications préalables
    Write-ColorText "`n🔍 Vérifications préalables..." $Yellow
    Write-Log 'INFO' 'Vérifications préalables' 'CHK00'
    try {
        $nodeVersion = node --version
        Write-ColorText "   ✓ Node.js: $nodeVersion" $Green
        $npmVersion = npm --version
        Write-ColorText "   ✓ npm: $npmVersion" $Green
    } catch {
        throw "Node.js n'est pas installé ou n'est pas dans le PATH"
    }
    $disk = Get-PSDrive -Name ((Get-Location).Path.Substring(0,1))
    Write-ColorText "   🖴 Espace libre: $([math]::Round($disk.Free/1MB)) MB" $Gray
    Write-ColorText "   👤 Utilisateur: $([System.Environment]::UserName)" $Gray
    try { New-Item -ItemType File -Path '.perm_test' -Force | Out-Null; Remove-Item '.perm_test' -Force }
    catch { throw "Permissions insuffisantes dans le répertoire" }

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
        Write-Log 'INFO' 'Nettoyage' 'CLEAN'
        Stop-BlockingProcesses
        Start-Sleep -Seconds 2
        @("out", "dist", ".vite", "release-builds", "build", ".webpack") | ForEach-Object {
            if (Test-Path $_) {
                try {
                    Invoke-WithRetry { Remove-Item -Path $_ -Recurse -Force -ErrorAction Stop } "clean $_"
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
    } else {
        Write-ColorText "`n🛠️ Mode Electron Builder (défaut)..." $Cyan
        $builderArgs = @(
            "--win",
            "--publish", "never",
            "--config.compression=normal",
            "--config.nsis.oneClick=false",
            "--config.nsis.allowElevation=true"
        )
        if ($Verbose) { $env:DEBUG = "electron-builder" }

        $buildSucceeded = $false
        Invoke-WithRetry { npx electron-builder @builderArgs } 'electron-builder'
        if ($LASTEXITCODE -eq 0) { $buildSucceeded = $true }

        if (-not $buildSucceeded) {
            Write-Log 'WARN' 'Electron-builder a échoué, fallback packager' 'EB01'
            Invoke-WithRetry { npx electron-builder --win --dir } 'builder-lite'
            if ($LASTEXITCODE -eq 0) { $buildSucceeded = $true }
        }

        if (-not $buildSucceeded) {
            Invoke-WithRetry {
                if (-not (Test-Path "node_modules\@electron\packager")) { npm install --save-dev @electron/packager }
            } 'install-packager'
            Invoke-WithRetry { npx electron-packager . "SyncOtter" --platform=win32 --arch=x64 --out=release-builds --overwrite --icon="src/assets/app-icon.ico" } 'electron-packager'
            if ($LASTEXITCODE -eq 0) { $buildSucceeded = $true }
        }

        if (-not $buildSucceeded) {
            Write-Log 'ERROR' 'Packager failed, copie manuelle' 'EB02'
            $manual = 'release-builds/manual'
            Remove-Item $manual -Recurse -Force -ErrorAction SilentlyContinue
            New-Item -ItemType Directory -Path $manual | Out-Null
            Copy-Item 'src' $manual -Recurse -Force
            Copy-Item 'package.json' $manual -Force
            $buildSucceeded = Test-Path $manual
        }

        if (-not $buildSucceeded) { throw 'Tous les modes de build ont échoué' }
    }

    $exe = Get-ChildItem -Path 'dist','release-builds' -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if(-not $exe){ throw 'EXE manquant apres build' }
    Write-ColorText "   ✓ Exe généré: $($exe.FullName)" $Green
    Write-Log 'SUCCESS' "Build OK: $($exe.Name)" 'END'
    Write-ColorText "`n✅ Build terminé avec succès!" $Green

} catch {
    Write-ColorText "`n❌ Erreur: $_" $Red
    Write-Log 'ERROR' ("Erreur: $_") 'FAIL'
    Write-ColorText "Stack trace:" $Red
    Write-ColorText $_.ScriptStackTrace $Gray
    if($Recovery -and (Test-Path $backupPath)){
        Write-Log 'WARN' 'Restauration depuis sauvegarde' 'REC01'
        Remove-Item 'dist' -Recurse -Force -ErrorAction SilentlyContinue
        Copy-Item $backupPath 'dist' -Recurse -Force -ErrorAction SilentlyContinue
    }
    exit 1
} finally {
    Pop-Location
    Remove-Item Env:DEBUG -ErrorAction SilentlyContinue
    if(Test-Path $backupPath -and -not $Recovery){
        Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-ColorText "`n✨ Script terminé!" $Green
Write-Log 'INFO' 'Script terminé' 'END'
Write-ColorText "💡 Utilisez -UseForge ou -UsePackager si electron-builder pose problème" $Cyan
