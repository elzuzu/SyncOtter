param(
    [switch]$Clean = $true
)

$Cyan = [ConsoleColor]::Cyan
$Green = [ConsoleColor]::Green
$Yellow = [ConsoleColor]::Yellow
$Red = [ConsoleColor]::Red

function Write-Col($text, $color){
    $old = $Host.UI.RawUI.ForegroundColor
    $Host.UI.RawUI.ForegroundColor = $color
    Write-Host $text
    $Host.UI.RawUI.ForegroundColor = $old
}

Write-Col "🚀 Build SyncOtter single-file (Deno)" $Cyan

try {
    if ($Clean -and (Test-Path 'deno-dist')) {
        Write-Col "🧹 Nettoyage..." $Yellow
        Remove-Item 'deno-dist' -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Get-Command deno -ErrorAction SilentlyContinue)) {
        Write-Col "📦 Deno non trouvé, installation requise" $Red
        throw "Deno n'est pas installé"
    }

    Write-Col "🏗️ Compilation avec Deno..." $Yellow
    & deno compile \
        --output "deno-dist/SyncOtter-Single.exe" \
        --allow-read --allow-write --allow-run --allow-env \
        src/deno-main.ts

    if ($LASTEXITCODE -ne 0) { throw 'deno compile a échoué' }

    Write-Col '✅ Build terminé' $Green
} catch {
    Write-Col "❌ Erreur: $($_.Exception.Message)" $Red
    exit 1
}
