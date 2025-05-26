param(
    [ValidateSet("portable", "installer", "dev", "ultra")]
    [string]$Type = "portable" # Default to portable if no type is specified
)

Write-Host "🦦 SyncOtter Build Script" -ForegroundColor Cyan
Write-Host "===========================" -ForegroundColor Cyan
Write-Host ""

# Function to check for command existence
function Test-CommandExists {
    param ([string]$command)
    Get-Command $command -ErrorAction SilentlyContinue -ErrorVariable +Errors | Out-Null
    return !$Errors
}

# 1. Verify Node.js
Write-Host "Verifying Node.js..."
if (-not (Test-CommandExists node)) {
    Write-Host "❌ Node.js not found. Please install Node.js LTS (e.g., from nodejs.org)." -ForegroundColor Red
    exit 1
}
$nodeVersion = node --version
Write-Host "✅ Node.js detected: $nodeVersion" -ForegroundColor Green

# 2. Verify npm
Write-Host "Verifying npm..."
if (-not (Test-CommandExists npm)) {
    Write-Host "❌ npm not found. It usually comes with Node.js." -ForegroundColor Red
    exit 1
}
$npmVersion = npm --version
Write-Host "✅ npm detected: $npmVersion" -ForegroundColor Green
Write-Host ""

# 3. Install dependencies if node_modules doesn't exist
if (-not (Test-Path "node_modules")) {
    Write-Host "📦 Installing dependencies (npm install)..." -ForegroundColor Yellow
    npm install --production --no-audit --no-fund # Using flags similar to user's example
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Dependency installation failed." -ForegroundColor Red
        exit 1
    }
    Write-Host "✅ Dependencies installed." -ForegroundColor Green
} else {
    Write-Host "✅ Dependencies already installed (node_modules folder found)." -ForegroundColor Green
}
Write-Host ""

# 4. Clean previous build output (assuming 'dist' directory)
$outputDir = "dist"
if (Test-Path $outputDir) {
    Write-Host "🧹 Cleaning previous build output from '$outputDir'..." -ForegroundColor Yellow
    try {
        Remove-Item -Recurse -Force $outputDir -ErrorAction Stop
        Write-Host "✅ Previous output cleaned." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Could not fully clean '$outputDir'. Error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}
Write-Host ""

# 5. Execute build based on Type
$buildSuccess = $false
switch ($Type) {
    "dev" {
        Write-Host "🧪 Launching in Development Mode..." -ForegroundColor Yellow
        npm start
        # For npm start, success is assumed if the command launches; actual exit code might vary.
        # We typically don't have artifacts to list for 'dev' mode.
        Write-Host "✅ Development mode started. Close the app or press Ctrl+C to stop." -ForegroundColor Green
        exit 0 # Exit script after starting dev mode
    }
    "installer" {
        Write-Host "🚀 Building Installer (electron-builder)..." -ForegroundColor Blue
        npm run build:installer
    }
    "portable" {
        Write-Host "🚀 Building Portable version (electron-builder)..." -ForegroundColor Blue
        npm run build:portable
    }
    "ultra" {
        Write-Host "🚀 Building Ultra-Light Portable version (electron-builder)..." -ForegroundColor Magenta
        # Potentially set environment variables if needed, e.g. for compression,
        # but current package.json scripts handle this via CLI args.
        # $env:ELECTRON_BUILDER_COMPRESSION_LEVEL = "maximum" # Example from user script, handled by package.json now
        npm run build:ultra
    }
    default {
        Write-Host "❌ Invalid build type '$Type' specified." -ForegroundColor Red
        exit 1
    }
}

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build failed for type '$Type'." -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ Build successful for type '$Type'!" -ForegroundColor Green
    $buildSuccess = $true
}
Write-Host ""

# 6. Display output file information (if build was successful and not dev mode)
if ($buildSuccess) {
    Write-Host "📦 Output files in '$outputDir':" -ForegroundColor Cyan
    $outputFiles = Get-ChildItem -Path $outputDir -Recurse -File | Where-Object { $_.Name -like "*.exe" -or $_.Name -like "*.zip" -or $_.Name -like "*.AppImage" -or $_.Name -like "*.dmg" } # Add other relevant extensions if needed
    
    if ($outputFiles.Count -eq 0) {
        Write-Host "No executables or archives found in '$outputDir'." -ForegroundColor Yellow
    } else {
        foreach ($file in $outputFiles) {
            $sizeMB = [math]::Round($file.Length / 1MB, 2)
            Write-Host "  - $($file.Name) ($($sizeMB) MB)" -ForegroundColor Green
        }
        if ($Type -eq "ultra" -or $Type -eq "portable") {
             Write-Host ""
             Write-Host "💡 Tip: Copy the .exe from '$outputDir' for use." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "🦦 SyncOtter Build Script Finished." -ForegroundColor Cyan
