param(
    [switch]$Clean = $true,
    [switch]$Compress = $true,
    [string]$Target,
    [switch]$UPX = $false,
    [switch]$Test = $false,
    [string]$UPXPath = 'upx'
)

function Get-DefaultNodeTarget {
    $envTarget = $env:PKG_NODE_TARGET
    if ($envTarget) { return $envTarget }
    try {
        $ver = (node -v 2>$null).Trim()
        if ($LASTEXITCODE -eq 0 -and $ver) {
            if ($ver.StartsWith('v')) { $ver = $ver.Substring(1) }
            $major = [int]$ver.Split('.')[0]

            # pkg 5.x ne supporte que Node 16/18
            if ($major -ge 16 -and $major -le 18) {
                return "node$major-win-x64"
            }

            Write-Col "⚠️ Node $major non supporté par pkg, fallback vers node18" $Yellow
        }
    } catch {}
    return 'node18-win-x64'
}

if (-not $Target) {
    $Target = Get-DefaultNodeTarget
}

$Cyan = [ConsoleColor]::Cyan
$Green = [ConsoleColor]::Green
$Yellow = [ConsoleColor]::Yellow
$Red = [ConsoleColor]::Red
$Gray = [ConsoleColor]::Gray

function Write-Col($text, $color){
    $old = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $color
    Write-Host $text
    $Host.UI.RawUI.ForegroundColor = $old
}

Write-Col "🚀 Build SyncOtter single-file (pkg)" $Cyan

try {
    if ($Clean) {
        Write-Col "🧹 Nettoyage..." $Yellow
        if (Test-Path 'pkg-dist') { Remove-Item 'pkg-dist' -Recurse -Force -ErrorAction SilentlyContinue }
        if (Test-Path 'node_modules') { Remove-Item 'node_modules' -Recurse -Force -ErrorAction SilentlyContinue }
    }

    if (-not (Get-Command pkg -ErrorAction SilentlyContinue)) {
        Write-Col "📦 Installation de pkg..." $Yellow
        npm install -g pkg
    }

    Write-Col "📥 Installation des dépendances production" $Yellow
    $env:NPM_CONFIG_PROGRESS = 'false'
    $env:NPM_CONFIG_FUND = 'false'
    if (Test-Path 'package-lock.json') {
        npm ci --only=production
    } else {
        npm install --production
    }
    if ($LASTEXITCODE -ne 0) { throw "npm install a échoué" }

    # Nettoyage avancé de node_modules
    Write-Col "🧹 Nettoyage avancé de node_modules" $Yellow

    # Supprimer les dossiers de test et de documentation
    Get-ChildItem -Path node_modules -Recurse -Directory 2>$null | Where-Object {
        $_.Name -in @('test','tests','__tests__','doc','docs')
    } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Supprimer certains fichiers inutiles
    Get-ChildItem -Path node_modules -Recurse -File -Include '*.md','*.markdown','*.ts','*.map' 2>$null |
        Remove-Item -Force -ErrorAction SilentlyContinue

    $compressArg = if ($Compress) { '--compress Brotli' } else { '' }
    $pkgCmd = "pkg main-cli.js --targets $Target $compressArg --no-bytecode --output pkg-dist/SyncOtter-Single.exe"
    Write-Col $pkgCmd $Gray
    Invoke-Expression $pkgCmd

    if ($LASTEXITCODE -ne 0) {
        throw 'pkg a échoué'
    }

    if (-not (Test-Path 'pkg-dist/SyncOtter-Single.exe')) {
        throw "pkg n'a pas généré pkg-dist/SyncOtter-Single.exe"
    }

    $exe = Get-Item 'pkg-dist/SyncOtter-Single.exe'
    $size = [Math]::Round($exe.Length / 1MB, 2)
    Write-Col "✅ Exécutable généré: $($exe.FullName) ($size MB)" $Green

    if ($UPX) {
        try {
            Write-Col "🗜️ Compression UPX..." $Yellow
            & $UPXPath $exe.FullName --best --lzma | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $exe = Get-Item $exe.FullName
                $size = [Math]::Round($exe.Length / 1MB, 2)
                Write-Col "✅ UPX terminé ($size MB)" $Green
            } else {
                Write-Col "⚠️ UPX a échoué" $Yellow
            }
        } catch {
            Write-Col "⚠️ UPX non disponible" $Yellow
        }
    }

    if ($Test) {
        Write-Col "🚀 Test de démarrage..." $Yellow
        $time = (Measure-Command { & $exe.FullName --help >$null }).TotalMilliseconds
        Write-Col "⏱️ Démarrage en $([math]::Round($time)) ms" $Green
    }

} catch {
    Write-Col "❌ Erreur: $($_.Exception.Message)" $Red
    exit 1
}

