param(
    [Parameter(Mandatory=$true)]
    [string]$DestinationPath,

    [string]$SourceDir = (Get-Location),
    [switch]$Rollback
)

function Get-Version {
    $pkg = Get-Content -Raw -Path (Join-Path $PSScriptRoot 'package.json') | ConvertFrom-Json
    return $pkg.version
}

function Deploy {
    $version = Get-Version
    # Chercher l'exe généré dynamiquement
    $exeFiles = Get-ChildItem "$SourceDir\dist" -Filter "*.exe" -ErrorAction SilentlyContinue
    if (-not $exeFiles) {
        throw "Aucun fichier .exe trouvé dans $SourceDir\dist"
    }
    $sourceExe = $exeFiles | Select-Object -First 1
    $target = Join-Path $DestinationPath "SyncOtter-$version.exe"
    Write-Host "Copying $($sourceExe.Name) to $target" -ForegroundColor Cyan
    Copy-Item $sourceExe.FullName $target -Force
    Copy-Item "$SourceDir\config.json" (Join-Path $DestinationPath 'config.json') -Force
    Set-Content -Path (Join-Path $DestinationPath 'current.txt') -Value $version
    Write-Host "Deployment complete" -ForegroundColor Green
}

function Rollback-Version {
    if(Test-Path (Join-Path $DestinationPath 'previous.txt')){
        $prev = Get-Content (Join-Path $DestinationPath 'previous.txt')
        $currentExe = Join-Path $DestinationPath "SyncOtter-$prev.exe"
        Write-Host "Rolling back to $prev" -ForegroundColor Yellow
        Set-Content -Path (Join-Path $DestinationPath 'current.txt') -Value $prev
    } else {
        Write-Host 'No previous version to rollback to' -ForegroundColor Red
    }
}

if($Rollback){
    Rollback-Version
}else{
    if(Test-Path (Join-Path $DestinationPath 'current.txt')){
        $current = Get-Content (Join-Path $DestinationPath 'current.txt')
        Set-Content -Path (Join-Path $DestinationPath 'previous.txt') -Value $current
    }
    Deploy
}
