param(
    [switch]$DryRun
)

$package = Get-Content package.json | ConvertFrom-Json
$nodeReq = $package.engines.node
$npmReq = $package.engines.npm

function Check-Version($cmd, $required) {
    try {
        $ver = & $cmd --version
        Write-Host "$cmd version $ver" -ForegroundColor Cyan
        return $true
    } catch {
        Write-Error "$cmd not found"
        return $false
    }
}

if ($DryRun) {
    Write-Host "Dry-run mode: system checks would be executed" -ForegroundColor Yellow
    return
}

$ok = $true
if (-not (Check-Version node $nodeReq)) { $ok = $false }
if (-not (Check-Version npm $npmReq)) { $ok = $false }

try {
    $drive = Get-PSDrive -Name ((Get-Location).Path.Substring(0,1))
    if ($drive.Free -lt 1GB) {
        Write-Error "Insufficient disk space (<1GB)"
        $ok = $false
    } else {
        Write-Host "Disk space: $([math]::Round($drive.Free / 1GB,2)) GB free" -ForegroundColor Cyan
    }
} catch {
    Write-Error "Unable to determine disk space"
    $ok = $false
}

try {
    $tmp = [System.IO.Path]::GetTempFileName()
    Remove-Item $tmp -ErrorAction SilentlyContinue
    Write-Host "Write permissions OK" -ForegroundColor Cyan
} catch {
    Write-Error "No write permissions in temp folder"
    $ok = $false
}

try {
    if (Test-Connection -Count 1 "registry.npmjs.org" -Quiet) {
        Write-Host "Network connectivity OK" -ForegroundColor Cyan
    } else {
        Write-Error "Network connectivity failed"
        $ok = $false
    }
} catch {
    Write-Error "Network test failed"
    $ok = $false
}

if (-not $ok) { exit 1 }
