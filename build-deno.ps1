param([switch]$Clean = $false, [switch]$ForceNative = $false, [switch]$NoConsole = $false)

# Couleurs
$Cyan = [ConsoleColor]::Cyan; $Green = [ConsoleColor]::Green; $Yellow = [ConsoleColor]::Yellow; $Red = [ConsoleColor]::Red
function Write-Col($text, $color) { $old = $Host.UI.RawUI.ForegroundColor; $Host.UI.RawUI.ForegroundColor = $color; Write-Host $text; $Host.UI.RawUI.ForegroundColor = $old }

Write-Col "🚀 SyncOtter Build System (All-in-One)" $Cyan
Write-Col "Options: -Clean (nettoyage), -ForceNative (mode natif), -NoConsole (version silencieuse)" $Yellow

try {
    # Nettoyage
    if ($Clean) {
        Write-Col "🧹 Nettoyage..." $Yellow
        @('deno-dist', 'src/deno-main-generated.ts') | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Recurse -Force } }
    }

    # Vérifications
    if (-not (Get-Command deno -ErrorAction SilentlyContinue)) { throw "Deno non installé" }
    $denoVersion = & deno --version 2>&1 | Select-Object -First 1
    Write-Col "📌 Version : $denoVersion" $Cyan

    # Stratégie de build
    $useNative = $ForceNative
    $mainFile = "src/deno-main.ts"
    
    if (-not $useNative) {
        if (-not (Test-Path $mainFile)) {
            $useNative = $true
            Write-Col "⚠️  Fichier original absent, mode natif" $Yellow
        } else {
            Write-Col "🔍 Test dépendances..." $Yellow
            $testResult = & deno cache --dry-run $mainFile 2>&1
            if ($LASTEXITCODE -ne 0 -or $testResult -match "UnknownIssuer|certificate|proxy") {
                $useNative = $true
                Write-Col "⚠️  Problème dépendances, mode natif" $Yellow
            } else {
                Write-Col "✅ Dépendances OK" $Green
            }
        }
    }

    # Génération version native si nécessaire
    if ($useNative) {
        Write-Col "🔧 Génération version native..." $Yellow
        if (-not (Test-Path "src")) { New-Item -ItemType Directory -Path "src" -Force | Out-Null }
        
        # Code TypeScript natif avec gestion externe du config.json
        $nativeCode = @"
/// <reference lib="deno.ns" />
// SyncOtter - Version native (sans dépendances externes)
// Config.json EXTERNE - doit être dans le même répertoire que l'exécutable

interface Config {
  sourceDirectory: string;
  targetDirectory: string;
  excludeDirectories?: string[];
  excludePatterns?: string[];
  executeAfterSync?: string;
  appName?: string;
  appDescription?: string;
  parallelCopies?: number;
  telemetryGranularity?: string;
}

function resolveConfigPath(): string {
  // PRIORITÉ 1 : config.json dans le répertoire de l'exécutable (EXTERNE)
  const exeDir = dirname(Deno.execPath());
  const externalConfig = join(exeDir, "config.json");
  
  console.log("🔍 Recherche config.json dans : " + exeDir);
  
  if (existsSync(externalConfig)) {
    console.log("✅ Config externe trouvé : " + externalConfig);
    return externalConfig;
  }
  
  // PRIORITÉ 2 : config.json dans le répertoire de travail (fallback)
  const workingDirConfig = join(Deno.cwd(), "config.json");
  console.log("🔍 Fallback - recherche dans : " + Deno.cwd());
  
  if (existsSync(workingDirConfig)) {
    console.log("⚠️  Config trouvé dans le répertoire de travail : " + workingDirConfig);
    return workingDirConfig;
  }
  
  // Aucun config trouvé
  throw new Error("❌ config.json non trouvé. Placez-le dans le même répertoire que l'exécutable : " + exeDir);
}

function existsSync(path: string): boolean {
  try { return Deno.statSync(path) != null; } catch { return false; }
}

async function ensureDir(path: string): Promise<void> {
  try { await Deno.mkdir(path, { recursive: true }); } 
  catch (error) { if (!(error instanceof Deno.errors.AlreadyExists)) throw error; }
}

function join(...paths: string[]): string {
  if (paths.length === 0) return '.';
  let joined = paths[0];
  for (let i = 1; i < paths.length; i++) {
    const path = paths[i];
    if (path.length > 0) {
      if (joined.endsWith('/') || joined.endsWith('\\')) {
        joined += path;
      } else {
        joined += (Deno.build.os === 'windows' ? '\\' : '/') + path;
      }
    }
  }
  return joined;
}

function dirname(path: string): string {
  const separator = Deno.build.os === 'windows' ? '\\' : '/';
  const lastSeparator = Math.max(path.lastIndexOf('/'), path.lastIndexOf('\\'));
  if (lastSeparator === -1) return '.';
  if (lastSeparator === 0) return separator;
  return path.slice(0, lastSeparator);
}

function relative(from: string, to: string): string {
  if (to.startsWith(from)) {
    const rel = to.slice(from.length);
    return rel.startsWith('/') || rel.startsWith('\\') ? rel.slice(1) : rel;
  }
  return to;
}

async function loadConfig(): Promise<Config> {
  const path = resolveConfigPath();
  
  try { 
    const data = await Deno.readTextFile(path);
    const config = JSON.parse(data);
    
    // Validation des champs obligatoires
    if (!config.sourceDirectory || !config.targetDirectory) {
      throw new Error("Les champs 'sourceDirectory' et 'targetDirectory' sont obligatoires dans config.json");
    }
    
    console.log("📄 Configuration chargée depuis : " + path);
    return config;
  } catch (error: any) {
    if (error.name === 'NotFound') {
      throw new Error("config.json manquant: " + path);
    } else if (error.name === 'SyntaxError') {
      throw new Error("config.json invalide (erreur JSON): " + error.message);
    } else {
      throw new Error("Erreur lecture config.json: " + error.message);
    }
  }
}

function shouldExclude(filePath: string, config: Config): boolean {
  const rel = relative(config.sourceDirectory, filePath);
  const parts = rel.split(/[\/\\]/);
  if (config.excludeDirectories && parts.some((p) => config.excludeDirectories!.includes(p))) return true;
  if (config.excludePatterns) {
    const name = parts[parts.length - 1];
    return config.excludePatterns.some((pattern) => {
      const regex = new RegExp(pattern.replace(/\*/g, ".*"));
      return regex.test(name);
    });
  }
  return false;
}

async function* walkDirectory(path: string): AsyncGenerator<{ path: string; isFile: boolean; isDirectory: boolean }> {
  try {
    for await (const entry of Deno.readDir(path)) {
      const fullPath = join(path, entry.name);
      if (entry.isFile) {
        yield { path: fullPath, isFile: true, isDirectory: false };
      } else if (entry.isDirectory) {
        yield { path: fullPath, isFile: false, isDirectory: true };
        yield* walkDirectory(fullPath);
      }
    }
  } catch (error: any) {
    console.warn("⚠️  Impossible de lire le dossier " + path + ": " + error.message);
  }
}

async function scanSourceFiles(config: Config): Promise<string[]> {
  const files: string[] = [];
  for await (const entry of walkDirectory(config.sourceDirectory)) {
    if (entry.isFile && !shouldExclude(entry.path, config)) {
      files.push(entry.path);
    }
  }
  return files;
}

async function copyFileIfNeeded(file: string, config: Config): Promise<boolean> {
  const rel = relative(config.sourceDirectory, file);
  const dest = join(config.targetDirectory, rel);
  await ensureDir(dirname(dest));

  try {
    const srcInfo = await Deno.stat(file);
    try {
      const destInfo = await Deno.stat(dest);
      if (destInfo.mtime?.getTime() === srcInfo.mtime?.getTime() && destInfo.size === srcInfo.size) {
        return false;
      }
    } catch { /* dest n'existe pas */ }
    
    await Deno.copyFile(file, dest);
    if (srcInfo.mtime) await Deno.utime(dest, srcInfo.atime || new Date(), srcInfo.mtime);
    return true;
  } catch (error: any) {
    console.warn("❌ Erreur copie " + file + ": " + error.message);
    return false;
  }
}

async function main() {
  console.log("🦦 SyncOtter - Synchronisation Ultra-Légère");
  console.log("📍 Exécutable : " + Deno.execPath());
  console.log("📁 Répertoire de travail : " + Deno.cwd());
  console.log("");
  
  const config = await loadConfig();
  
  // Afficher les informations de configuration
  if (config.appName) console.log("📋 Application : " + config.appName);
  if (config.appDescription) console.log("📄 Description : " + config.appDescription);
  
  console.log("📂 Source : " + config.sourceDirectory);
  console.log("📁 Cible : " + config.targetDirectory);
  
  if (config.excludeDirectories && config.excludeDirectories.length > 0) {
    console.log("🚫 Dossiers exclus : " + config.excludeDirectories.join(", "));
  }
  if (config.excludePatterns && config.excludePatterns.length > 0) {
    console.log("🚫 Patterns exclus : " + config.excludePatterns.join(", "));
  }
  console.log("");
  
  await ensureDir(config.targetDirectory);
  console.log("🔍 Analyse des fichiers sources...");
  const files = await scanSourceFiles(config);
  console.log("📥 " + files.length + " fichiers trouvés");

  let copied = 0, skipped = 0;
  for (let i = 0; i < files.length; i++) {
    const file = files[i];
    const wasCopied = await copyFileIfNeeded(file, config);
    
    if (wasCopied) {
      copied++;
      const relPath = relative(config.sourceDirectory, file);
      if (config.telemetryGranularity === "detailed" || !config.telemetryGranularity) {
        console.log("   ✅ " + (i+1) + "/" + files.length + " - Copié: " + relPath);
      }
    } else {
      skipped++;
      if (config.telemetryGranularity === "detailed" && skipped % 50 === 0) {
        console.log("   ⏭️  " + (i+1) + "/" + files.length + " - " + skipped + " fichiers identiques ignorés");
      }
    }
    
    // Affichage du progrès pour les gros volumes
    if ((i + 1) % 1000 === 0) {
      console.log("   📊 Progression: " + (i+1) + "/" + files.length + " (" + Math.round((i+1)/files.length*100) + "%)");
    }
  }

  console.log("");
  console.log("📊 Résumé: " + copied + " fichiers copiés, " + skipped + " fichiers ignorés");

  if (config.executeAfterSync) {
    console.log("🚀 Lancement de: " + config.executeAfterSync);
    try {
      const cmd = new Deno.Command(config.executeAfterSync, { args: [] });
      const child = cmd.spawn();
      await child.status;
      console.log("✅ Application lancée avec succès");
    } catch (error: any) {
      console.warn("⚠️  Impossible de lancer " + config.executeAfterSync + ": " + error.message);
    }
  }

  console.log("✅ Synchronisation terminée");
}

if (import.meta.main) {
  main().catch((error: any) => {
    console.error("❌ ERREUR: " + error.message);
    console.error("");
    console.error("💡 Vérifiez que config.json est dans le même répertoire que l'exécutable");
    console.error("📁 Répertoire attendu: " + dirname(Deno.execPath()));
    
    if (Deno.build.os === 'windows') {
      console.error("");
      console.error("Appuyez sur une touche pour fermer...");
      // Pause pour permettre de lire l'erreur
      Deno.stdin.read(new Uint8Array(1));
    }
    
    Deno.exit(1);
  });
}
"@
        
        $nativeCode | Out-File -FilePath "src/deno-main-generated.ts" -Encoding UTF8
        $mainFile = "src/deno-main-generated.ts"
        Write-Col "   ✅ Version native créée" $Green
    }

    # Compilation
    Write-Col "`n🏗️  Compilation..." $Yellow
    if (-not (Test-Path 'deno-dist')) { New-Item -ItemType Directory -Path 'deno-dist' -Force | Out-Null }
    
    $outputName = if ($useNative) { "SyncOtter-Native.exe" } else { "SyncOtter.exe" }
    
    # Définir les variables d'environnement pour ignorer les certificats SSL
    $env:DENO_TLS_CA_STORE = "system,mozilla"
    $env:NODE_TLS_REJECT_UNAUTHORIZED = "0"
    
    # Compilation avec gestion des erreurs TypeScript
    Write-Col "   Tentative 1 : Compilation standard..." $Yellow
    & deno compile --output "deno-dist/$outputName" --allow-all $mainFile
    
    # Si échec, essayer sans vérification de types
    if ($LASTEXITCODE -ne 0) {
        Write-Col "   Tentative 2 : Compilation avec --no-check..." $Yellow
        & deno compile --no-check --output "deno-dist/$outputName" --allow-all $mainFile
    }
    
    # Si échec, essayer avec curl pour pré-télécharger le runtime
    if ($LASTEXITCODE -ne 0 -and (Get-Command curl -ErrorAction SilentlyContinue)) {
        Write-Col "   Tentative 3 : Pré-téléchargement du runtime avec curl..." $Yellow
        
        # Créer le dossier cache Deno s'il n'existe pas
        $denoDir = if ($env:DENO_DIR) { $env:DENO_DIR } else { "$env:USERPROFILE\.deno" }
        $runtimeDir = "$denoDir\dl\release\v2.3.5"
        if (-not (Test-Path $runtimeDir)) { New-Item -ItemType Directory -Path $runtimeDir -Force | Out-Null }
        
        # URL du runtime pour Windows x64
        $runtimeUrl = "https://dl.deno.land/release/v2.3.5/denort-x86_64-pc-windows-msvc.zip"
        $runtimeFile = "$runtimeDir\denort-x86_64-pc-windows-msvc.zip"
        
        if (-not (Test-Path $runtimeFile)) {
            Write-Col "     📥 Téléchargement du runtime Deno..." $Cyan
            & curl -L --ssl-no-revoke --insecure -o $runtimeFile $runtimeUrl
            if ($LASTEXITCODE -eq 0) {
                Write-Col "     ✅ Runtime téléchargé avec succès" $Green
                # Retry compilation
                & deno compile --no-check --output "deno-dist/$outputName" --allow-all $mainFile
            }
        } else {
            Write-Col "     ✅ Runtime déjà présent" $Green
            # Retry compilation
            & deno compile --no-check --output "deno-dist/$outputName" --allow-all $mainFile
        }
    }
    
    # Dernière tentative : bundle + wrapper
    if ($LASTEXITCODE -ne 0) {
        Write-Col "   Tentative 4 : Création d'un bundle JavaScript..." $Yellow
        $bundleFile = "deno-dist/SyncOtter-Bundle.js"
        & deno bundle --no-check $mainFile $bundleFile
        
        if ($LASTEXITCODE -eq 0) {
            # Créer un wrapper batch pour le bundle
            $wrapperFile = "deno-dist/SyncOtter-Bundle.bat"
            $wrapperContent = @"
@echo off
deno run --allow-read --allow-write --allow-run --allow-env "%~dp0SyncOtter-Bundle.js" %*
"@
            $wrapperContent | Out-File -FilePath $wrapperFile -Encoding ASCII
            Write-Col "     ✅ Bundle créé : $bundleFile + $wrapperFile" $Green
            $outputName = "SyncOtter-Bundle.bat"
        } else {
            throw "Toutes les tentatives de compilation ont échoué"
        }
    }

    # Résultat
    Write-Col "`n✅ Build terminé : 'deno-dist/$outputName'" $Green

    # Copier les ressources du splash screen pour la version compilée
    if (Test-Path 'web') {
        Copy-Item -Path 'web' -Destination 'deno-dist' -Recurse -Force
        Write-Col "📂 Dossier 'web' copié dans deno-dist" $Cyan
    }
    
    # Créer une version sans console si demandé (Windows uniquement)
    if ($NoConsole -and $outputName.EndsWith('.exe') -and (Test-Path "deno-dist/$outputName")) {
        Write-Col "`n🔇 Création de la version sans console..." $Yellow
        
        # 1. Script VBS pour lancer sans aucune fenêtre
        $noConsoleWrapper = "deno-dist/SyncOtter-Silent.vbs"
        $vbsContent = @"
Dim shell, fso, scriptDir, exePath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

' Obtenir le répertoire du script VBS
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
exePath = scriptDir & "\$outputName"

' Lancer l'exe de manière complètement invisible (WindowStyle = 0)
shell.Run """" & exePath & """", 0, True

Set shell = Nothing
Set fso = Nothing
"@
        $vbsContent | Out-File -FilePath $noConsoleWrapper -Encoding ASCII
        
        # 2. Script PowerShell pour lancement silencieux
        $silentPS1 = "deno-dist/SyncOtter-Silent.ps1"
        $ps1Content = @"
# Lance SyncOtter sans fenêtre console visible
`$processInfo = New-Object System.Diagnostics.ProcessStartInfo
`$processInfo.FileName = "`$PSScriptRoot\$outputName"
`$processInfo.UseShellExecute = `$false
`$processInfo.CreateNoWindow = `$true
`$processInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

`$process = [System.Diagnostics.Process]::Start(`$processInfo)
`$process.WaitForExit()

# Optionnel : afficher le code de sortie
if (`$process.ExitCode -ne 0) {
    Write-Warning "SyncOtter s'est terminé avec le code d'erreur: `$(`$process.ExitCode)"
}
"@
        $ps1Content | Out-File -FilePath $silentPS1 -Encoding UTF8
        
        # 3. Créer un exécutable wrapper C# compilé à la volée (solution la plus propre)
        $wrapperCS = "deno-dist/SyncOtter-Wrapper.cs"
        $csContent = @"
using System;
using System.Diagnostics;
using System.IO;

class Program
{
    static void Main()
    {
        try
        {
            string exePath = Path.Combine(Path.GetDirectoryName(System.Reflection.Assembly.GetExecutingAssembly().Location), "$outputName");
            
            ProcessStartInfo startInfo = new ProcessStartInfo
            {
                FileName = exePath,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };
            
            Process process = Process.Start(startInfo);
            process.WaitForExit();
            Environment.Exit(process.ExitCode);
        }
        catch (Exception ex)
        {
            // En cas d'erreur, on ne fait rien (mode silencieux)
            Environment.Exit(1);
        }
    }
}
"@
        $csContent | Out-File -FilePath $wrapperCS -Encoding UTF8
        
        # Tenter de compiler le wrapper C# si csc.exe est disponible
        $csc = Get-Command "csc.exe" -ErrorAction SilentlyContinue
        if ($csc) {
            Write-Col "     🔨 Compilation du wrapper C#..." $Cyan
            $wrapperExe = "deno-dist/SyncOtter-Silent.exe"
            & csc.exe /out:$wrapperExe /target:winexe /nologo $wrapperCS 2>$null
            if ($LASTEXITCODE -eq 0) {
                Remove-Item $wrapperCS -Force
                Write-Col "     ✅ Wrapper C# compilé : SyncOtter-Silent.exe" $Green
            }
        }
        
        Write-Col "   ✅ Versions silencieuses créées :" $Green
        Write-Col "     📄 SyncOtter-Silent.vbs (recommandé - aucune fenêtre)" $Cyan
        Write-Col "     📄 SyncOtter-Silent.ps1 (PowerShell sans console)" $Cyan
        if (Test-Path "deno-dist/SyncOtter-Silent.exe") {
            Write-Col "     📄 SyncOtter-Silent.exe (C# natif - aucune fenêtre)" $Green
        }
    }
    
    if (Test-Path "deno-dist/$outputName") {
        $fileSize = [math]::Round((Get-Item "deno-dist/$outputName").Length / 1MB, 2)
        Write-Col "📊 Taille : $fileSize MB" $Cyan
    }
    
    $modeText = if ($useNative) { "natif (sans dépendances)" } else { "standard" }
    Write-Col "🎉 Build réussi en mode $modeText !" $Green
    if ($useNative) { Write-Col "💡 Compatible avec tous les proxies d'entreprise" $Cyan }
    
    Write-Col "`n🚀 Utilisation :" $Green
    Write-Col "   📄 config.json doit être dans le MÊME répertoire que l'exécutable" $Yellow
    Write-Col "   ▶️  .\deno-dist\$outputName" $Cyan
    
    if ($NoConsole -and (Test-Path "deno-dist/SyncOtter-Silent.vbs")) {
        Write-Col "`n🔇 Mode silencieux disponible :" $Green
        Write-Col "   🥇 .\deno-dist\SyncOtter-Silent.vbs (RECOMMANDÉ - aucune fenêtre)" $Green
        Write-Col "   🥈 .\deno-dist\SyncOtter-Silent.ps1 (PowerShell invisible)" $Cyan
        if (Test-Path "deno-dist/SyncOtter-Silent.exe") {
            Write-Col "   🏆 .\deno-dist\SyncOtter-Silent.exe (C# natif - aucune fenêtre)" $Green
        }
        Write-Col "" 
        Write-Col "   💡 Double-cliquez sur SyncOtter-Silent.vbs pour une exécution complètement invisible" $Yellow
    }
    
    Write-Col "`n📋 Configuration externe :" $Green
    Write-Col "   📁 Copiez deno-dist/$outputName + config.json ensemble" $Cyan
    Write-Col "   🔧 L'exécutable cherche automatiquement config.json à côté de lui" $Cyan

} catch {
    Write-Col "`n❌ Erreur : $($_.Exception.Message)" $Red
    exit 1
}
