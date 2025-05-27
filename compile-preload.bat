@echo off
echo Compilation du preload.ts...

:: Installer TypeScript si necessaire
if not exist "node_modules\typescript" (
    echo Installation de TypeScript...
    call npm install --save-dev typescript
)

:: Compiler le fichier
call npx tsc src\preload.ts --outDir src --module commonjs --target es2020 --esModuleInterop --skipLibCheck

if errorlevel 1 (
    echo ERREUR: Compilation echouee!
    pause
    exit /b 1
)

echo Compilation terminee: src\preload.js
pause
