# Script de build pour SyncOtter
param(
    [switch]$Clean = $true,
    [switch]$InstallDeps = $false,
    [switch]$Verbose = $false,
    [switch]$UseForge = $false,
    [switch]$UsePackager = $false,
    [switch]$UseWebpack = $false,
    [switch]$Stealth = $false,
    [switch]$Recovery = $false,
    [switch]$CliMode = $false,
    [switch]$LoaderMode = $false,
    [switch]$UltraLight = $false,
    [switch]$HybridMode = $false
)

# Répertoire du projet
$projectRoot = $PSScriptRoot

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
    param(
        [ScriptBlock]$Action,
        [string]$Name,
        [switch]$Npm
    )
    $attempt = 0
    while ($attempt -lt 3) {
        try {
            $global:LASTEXITCODE = 0
            & $Action
            if ($LASTEXITCODE -eq 0) { return }
            $err = "Code $LASTEXITCODE"
        } catch {
            $err = $_
        }

        $attempt++
        Write-Log 'WARN' "Echec $Name tentative $attempt : $err" 'RETRY'
        Stop-BlockingProcesses
        if ($Npm) { npm cache clean --force | Out-Null }
        if ($attempt -ge 3) { throw $err }
        Start-Sleep -Seconds 1
    }
}

function Stop-BlockingProcesses {
    Get-Process node*,electron* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Wait-AndCleanupJobs {
    param($Jobs)
    if(-not $Jobs -or $Jobs.Count -eq 0){ return }
    Wait-Job $Jobs
    foreach($j in $Jobs){
        if($j.State -eq 'Failed'){
            $err = Receive-Job $j -ErrorAction SilentlyContinue
            Remove-Job $j
            throw $err
        }
        Receive-Job $j | Out-Null
        Remove-Job $j
    }
    if ($Jobs -is [System.Collections.IList]) { $Jobs.Clear() }
}

function Write-ColorText($Text, $Color) {
    if(-not $Stealth){
        $currentColor = $Host.UI.RawUI.ForegroundColor
        $Host.UI.RawUI.ForegroundColor = $Color
        Write-Host $Text
        $Host.UI.RawUI.ForegroundColor = $currentColor
    }
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
    if (-not (Test-IsAdmin)) {
        Write-ColorText "   ⚠️ Certains fichiers peuvent nécessiter les droits administrateur" $Yellow
    }
    $paths = @()
    if ($env:USERPROFILE) {
        $paths += Join-Path -Path $env:USERPROFILE -ChildPath ".cache\electron-builder"
    }
    if ($env:LOCALAPPDATA) {
        $paths += Join-Path -Path $env:LOCALAPPDATA -ChildPath "electron-builder\cache"
    }
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
# Vérification de l'état npm
function Test-NpmHealth {
    try {
        $output = npm ls --depth=0 --json 2>&1
        $code = $LASTEXITCODE
        if ($code -ne 0) {
            Write-Log 'WARN' "npm ls a retourné $code : $output" 'NPM'
            return $false
        }
        return $true
    } catch {
        Write-Log 'WARN' "npm ls exception : $_" 'NPM'
        return $false
    }
}



# Détection automatique de l'architecture
$envArch = $env:PROCESSOR_ARCHITECTURE
if ($envArch -match 'ARM64') {
    $DetectedArch = 'arm64'
} else {
    $DetectedArch = 'x64'
}
$AllArchitectures = @($DetectedArch)

function Test-BuildCache {
    $cacheFile = Join-Path $projectRoot '.buildcache'

    # Récupérer les fichiers source avec gestion d'erreur
    $files = @()
    if (Test-Path "$projectRoot\src") {
        $files += Get-ChildItem -Path "$projectRoot\src" -Recurse -File -ErrorAction SilentlyContinue
    } else {
        Write-ColorText "   ⚠️ Dossier src introuvable" $Yellow
    }

    # Ajouter package-lock.json s'il existe
    $packageLockPath = "$projectRoot\package-lock.json"
    if (Test-Path $packageLockPath) {
        $files += Get-Item $packageLockPath -ErrorAction SilentlyContinue
    }

    # Calculer le hash de tous les fichiers
    if ($files.Count -gt 0) {
        $hash = ($files | Get-FileHash -Algorithm SHA256 -ErrorAction SilentlyContinue | ForEach-Object { $_.Hash }) -join ''
    } else {
        $hash = "empty"
    }

    # Vérifier le cache
    if (Test-Path $cacheFile) {
        $old = Get-Content $cacheFile -Raw -ErrorAction SilentlyContinue
        if ($old -eq $hash) {
            Write-ColorText "✅ Build déjà à jour (cache hit)" $Green
            return $true
        }
    }

    # Sauvegarder le nouveau hash
    Set-Content -Path $cacheFile -Value $hash -ErrorAction SilentlyContinue
    return $false
}

function Invoke-TreeShaking {
    Write-ColorText "`n🌳 Tree-shaking des modules inutilisés..." $Yellow
    if (-not (Test-Path 'node_modules')) { return }
    try {
        $deps = (Get-Content package.json -Raw | ConvertFrom-Json).dependencies.Keys
        Get-ChildItem node_modules -Directory | Where-Object { $_.Name -ne '.bin' -and $deps -notcontains $_.Name } | ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-ColorText "   🗑️ Module inutilisé supprimé: $($_.Name)" $Gray
        }
    } catch {
        Write-ColorText "   ⚠️ Tree-shaking impossible" $Yellow
    }
}

function Minify-Sources {
    Write-ColorText "`n🔐 Minification JS/HTML..." $Yellow
    if (-not (Get-Command npx -ErrorAction SilentlyContinue)) {
        Write-ColorText "   ⚠️ npx introuvable, minification ignorée" $Yellow
        return
    }
    $needed = @('terser','html-minifier') | Where-Object { -not (Test-Path "node_modules/$_") }
    if ($needed.Count -gt 0) {
        Write-ColorText "   📦 Installation des outils de minification..." $Yellow
        $pkgList = $needed -join ' '
        Invoke-WithRetry { npm install --save-dev $pkgList } 'install-minify-tools' -Npm
    }
    if (-not (Test-Path 'node_modules/terser') -or -not (Test-Path 'node_modules/html-minifier')) {
        Write-ColorText "   ⚠️ Minification ignorée: outils manquants" $Yellow
        return
    }
    Get-ChildItem src -Recurse -Include *.js | ForEach-Object {
        Invoke-Step "npx terser $_.FullName -c -m -o $_.FullName"
    }
    Get-ChildItem src -Recurse -Include *.html | ForEach-Object {
        Invoke-Step "npx html-minifier $_.FullName -o $_.FullName --collapse-whitespace --remove-comments"
    }
}

function Compress-Assets {
    Write-ColorText "`n📦 Compression Brotli des assets..." $Yellow
    $assetDir = "src\assets"
    if (-not (Test-Path $assetDir)) {
        Write-ColorText "   ⚠️ Dossier $assetDir introuvable, compression ignorée" $Yellow
        return
    }
    try {
        Get-ChildItem $assetDir -Recurse -File | ForEach-Object {
            $dest = "$($_.FullName).br"
            $in = [IO.File]::OpenRead($_.FullName)
            $out = [IO.File]::Create($dest)
            $br = New-Object IO.Compression.BrotliStream($out, [IO.Compression.CompressionLevel]::Optimal)
            $in.CopyTo($br); $br.Dispose(); $out.Dispose(); $in.Dispose()
        }
    } catch {
        Write-ColorText "   ⚠️ Compression Brotli échouée: $_" $Yellow
    }
}

function Compress-Executable($exePath) {
    if (Get-Command upx -ErrorAction SilentlyContinue) {
        Write-ColorText "`n📦 Compression UPX..." $Yellow
        Invoke-Step "upx --best $exePath"
    } else {
        Write-ColorText "   ⚠️ UPX non trouvé" $Yellow
    }
}

function Invoke-Step($command) {
    if ($Stealth) {
        Invoke-Expression $command | Out-Null
    } else {
        Invoke-Expression $command
    }
}


$projectRoot = $PSScriptRoot
Write-ColorText "🚀 Répertoire du projet: $projectRoot" $Cyan

if (-not ($CliMode -or $LoaderMode -or $UltraLight -or $HybridMode)) {
    Write-ColorText "🔍 Détection du meilleur mode..." $Yellow
    # Placeholder: ici on pourrait analyser l'environnement pour choisir le mode optimal
}

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
    foreach ($cmd in 'node','npm','npx') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            throw "$cmd n'est pas disponible dans le PATH"
        }
    }
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

    if (Test-BuildCache -and -not $Clean) {
        Write-ColorText "✅ Build déjà à jour" $Green
        return
    }

    $iconPath = "src\assets\app-icon.ico"
    if (Test-Path $iconPath) {
        Write-ColorText "   ✓ Icône trouvée: $iconPath" $Green
    } else {
        Write-ColorText "   ⚠️ Icône manquante, création d'une icône par défaut..." $Yellow
        $assetsDir = "src\assets"
        if (-not (Test-Path $assetsDir)) {
            New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null
        }
        $iconBase64 = @(
            'AAABAAEAAQEAAAAAAABDAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAABAAAAAQgEAAAAtRwMAgAAAAtJREFUeNpj/M/AAAYAA7gdlCsAAAAASUVORK5CYII='
        ) -join ''
        [IO.File]::WriteAllBytes($iconPath, [Convert]::FromBase64String($iconBase64))
        Write-ColorText "   ✓ Icône par défaut créée: $iconPath" $Green
        Write-ColorText "   ⚠️ ATTENTION: Remplacez cette icône par votre icône personnalisée" $Yellow
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

    $jobs = @()

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

    $installed = $false
    if ($InstallDeps -or -not (Test-Path "node_modules")) {
        Write-ColorText "`n📦 Installation des dépendances..." $Yellow
        if ($InstallDeps -and (Test-Path "node_modules")) {
            Write-ColorText "   🗑️ Suppression de node_modules..." $Yellow
            Remove-Item -Path "node_modules" -Recurse -Force -ErrorAction SilentlyContinue
        }
        npm cache clean --force | Out-Null
        $jobs.Add((Start-Job -ArgumentList $Stealth -ScriptBlock {
            param($s)
            if ($s) { npm install | Out-Null } else { npm install }
            if ($LASTEXITCODE -ne 0) { throw "deps" }
        })) | Out-Null
        Wait-AndCleanupJobs $jobs
        $installed = $true
    }

    if (-not (Test-NpmHealth)) {
        Write-ColorText "   ⚠️ Conflits npm détectés, tentative de résolution..." $Yellow
        Invoke-WithRetry { npm install --legacy-peer-deps } 'npm-fix' -Npm
    }

    Write-ColorText "`n📝 Compilation de preload.ts..." $Yellow
    $tscAvailable = $true
    if (-not (Get-Command tsc -ErrorAction SilentlyContinue) -and -not (Test-Path "node_modules\typescript")) {
        Write-ColorText "   📦 Installation de TypeScript et types Electron..." $Yellow
        Invoke-WithRetry { npm install --save-dev typescript @types/electron @types/node } 'install-ts' -Npm
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path "node_modules\typescript")) {
            Write-ColorText "   ⚠️ Installation TypeScript échouée" $Yellow
            $tscAvailable = $false
        }
    }
    if ($tscAvailable) {
        $jobs.Add((Start-Job -ArgumentList $Stealth -ScriptBlock {
            param($s)
            $tscCommand = "npx tsc src\preload.ts --outDir src --module commonjs --target es2020 --esModuleInterop --skipLibCheck --allowSyntheticDefaultImports --moduleResolution node"
            if ($s) {
                Invoke-Expression $tscCommand | Out-Null
            } else {
                Invoke-Expression $tscCommand
            }
            if ($LASTEXITCODE -ne 0) { throw "tsc" }
        })) | Out-Null
        Wait-AndCleanupJobs $jobs
    } else {
        Write-ColorText "   ⚠️ TypeScript non disponible, tentative fallback" $Yellow
        $nodeScript = @'
const fs = require("fs");
const tsFile = "src/preload.ts";
const jsFile = "src/preload.js";
let source = fs.readFileSync(tsFile, "utf8");
try {
  const ts = require("typescript");
  const result = ts.transpileModule(source, { compilerOptions: { module: "CommonJS", target: "ES2020", esModuleInterop: true } });
  fs.writeFileSync(jsFile, result.outputText);
} catch(e) {
  source = source.replace(/import\s+\{([^}]+)\}\s+from\s+['"]electron['"];?/, 'const {$1} = require("electron");');
  source = source.replace(/:\s*[^=,)]+/g, '');
  fs.writeFileSync(jsFile, source);
}
'@
        node -e $nodeScript
    }

    if ($jobs.Count -gt 0) {
        Wait-AndCleanupJobs $jobs
        Write-ColorText "✅ Tâches parallèles terminées" $Green
        if ($installed) { Write-ColorText "✅ Dépendances installées" $Green }
    }
    # Vérifier la compilation
    $preloadJsPath = "src\preload.js"
    if (-not (Test-Path $preloadJsPath)) { 
        Write-ColorText "❌ Fichier preload.js manquant après compilation" $Red
        Write-ColorText "Tentative de compilation manuelle..." $Yellow
        try {
            npx tsc src\preload.ts --outDir src --module commonjs --target es2020 --esModuleInterop --skipLibCheck --allowSyntheticDefaultImports --moduleResolution node
            if (-not (Test-Path $preloadJsPath)) {
                throw "Compilation manuelle échouée"
            }
        } catch {
            throw "Compilation de preload.ts echouée : $_"
        }
    }
    Write-ColorText "   ✓ preload.ts compilé avec succès" $Green
    if ($InstallDeps -or -not (Test-Path "node_modules")) { Invoke-TreeShaking }
    Minify-Sources
    Compress-Assets

    if ($CliMode) {
        Write-ColorText "`n🔧 Mode CLI..." $Cyan
        if (-not (Test-Path 'package-cli.json')) { throw 'package-cli.json manquant' }
        Invoke-Step "npx pkg -C GZip -t node18-win-x64 src/cli-main.js --out-path dist"
        $cliExe = Get-ChildItem -Path 'dist' -Filter *.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cliExe) { Compress-Executable $cliExe.FullName }
        Write-ColorText "   ✓ Exe CLI généré: $($cliExe.FullName)" $Green
        Write-Log 'SUCCESS' 'Build CLI OK' 'END'
        return
    }

    if ($UseWebpack) {
        Write-ColorText "`n📦 Bundling Webpack..." $Yellow
        Invoke-Step "node build-ultra.js"
    }

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
        npx electron-packager . "SyncOtter" --platform=win32 --arch=$DetectedArch --out=release-builds --overwrite --icon="src/assets/app-icon.ico"
    } else {
        Write-ColorText "`n🛠️ Mode Electron Builder (défaut)..." $Cyan
        $archArgs = if ($DetectedArch -eq 'arm64') { @('--arm64') } else { @('--x64') }

        $builderArgs = @("--win") + $archArgs + @(
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
            Write-Log 'WARN' 'Electron-builder a échoué, tentative builder-lite' 'EB01'
            Invoke-WithRetry { npx electron-builder --win --dir } 'builder-lite'
            if ($LASTEXITCODE -eq 0) { $buildSucceeded = $true }
        }

        if (-not $buildSucceeded) {
            Invoke-WithRetry {
                if (-not (Test-Path "node_modules\@electron\packager")) { npm install --save-dev @electron/packager }
            } 'install-packager' -Npm
            Invoke-WithRetry { npx electron-packager . "SyncOtter" --platform=win32 --arch=$DetectedArch --out=release-builds --overwrite --icon="src/assets/app-icon.ico" } 'electron-packager'
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
    Compress-Executable $exe.FullName
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
    try { Pop-Location } catch {}
    try { Remove-Item Env:DEBUG -ErrorAction SilentlyContinue } catch {}
    try {
        if ((Test-Path $backupPath) -and (-not $Recovery)) {
            Remove-Item $backupPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Write-ColorText "`n✨ Script terminé!" $Green
Write-Log 'INFO' 'Script terminé' 'END'
Write-ColorText "💡 Utilisez -UseForge ou -UsePackager si electron-builder pose problème" $Cyan
