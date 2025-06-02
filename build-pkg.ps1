param(
    [switch]$Clean = $true,
    [switch]$Compress = $true,
    [string]$Target = 'node18-win-x64'
)

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
npm install --production
if ($LASTEXITCODE -ne 0) { throw "npm install a échoué" }

$compressArg = if ($Compress) { '--compress Brotli' } else { '' }
$pkgCmd = "pkg main-cli.js --targets $Target $compressArg --output pkg-dist/SyncOtter-Single.exe"
Write-Col $pkgCmd $Gray
Invoke-Expression $pkgCmd
if ($LASTEXITCODE -ne 0) { throw 'pkg a échoué' }

$exe = Get-Item 'pkg-dist/SyncOtter-Single.exe'
$size = [Math]::Round($exe.Length / 1MB, 2)
Write-Col "✅ Exécutable généré: $($exe.FullName) ($size MB)" $Green
