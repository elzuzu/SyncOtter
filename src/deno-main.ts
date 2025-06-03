import { ensureDir, exists } from "https://deno.land/std@0.208.0/fs/mod.ts";
import { walk } from "https://deno.land/std@0.208.0/fs/walk.ts";
import { join, relative, dirname } from "https://deno.land/std@0.208.0/path/mod.ts";

interface Config {
  sourceDirectory: string;
  targetDirectory: string;
  excludeDirectories?: string[];
  excludePatterns?: string[];
  executeAfterSync?: string;
}

function resolveConfigPath(): string {
  const exeDir = dirname(Deno.execPath());
  const local = join(exeDir, "config.json");
  if (existsSync(local)) return local;
  return join(Deno.cwd(), "config.json");
}

function existsSync(p: string): boolean {
  try {
    return Deno.statSync(p) != null;
  } catch {
    return false;
  }
}

async function loadConfig(): Promise<Config> {
  const path = resolveConfigPath();
  if (!await exists(path)) {
    throw new Error(`config.json manquant: ${path}`);
  }
  const data = await Deno.readTextFile(path);
  return JSON.parse(data);
}

function shouldExclude(filePath: string, config: Config): boolean {
  const rel = relative(config.sourceDirectory, filePath);
  const parts = rel.split(/[/\\]/);
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

async function scanSourceFiles(config: Config): Promise<string[]> {
  const files: string[] = [];
  for await (const entry of walk(config.sourceDirectory)) {
    if (entry.isFile && !shouldExclude(entry.path, config)) {
      files.push(entry.path);
    }
  }
  return files;
}

async function copyFileIfNeeded(file: string, config: Config) {
  const rel = relative(config.sourceDirectory, file);
  const dest = join(config.targetDirectory, rel);
  await ensureDir(dirname(dest));

  try {
    const srcInfo = await Deno.stat(file);
    const destExists = await exists(dest);
    if (destExists) {
      const destInfo = await Deno.stat(dest);
      if (destInfo.mtime?.getTime() === srcInfo.mtime?.getTime() && destInfo.size === srcInfo.size) {
        return;
      }
    }
  } catch {
    // ignore comparison errors
  }

  await Deno.copyFile(file, dest);
}

async function main() {
  const config = await loadConfig();
  await ensureDir(config.targetDirectory);
  const files = await scanSourceFiles(config);
  console.log(`📥 ${files.length} fichiers à synchroniser`);

  let copied = 0;
  for (const file of files) {
    await copyFileIfNeeded(file, config);
    copied++;
    console.log(`   ${copied}/${files.length} - ${file}`);
  }

  if (config.executeAfterSync) {
    try {
      const cmd = new Deno.Command(config.executeAfterSync, { args: [] });
      await cmd.spawn().status;
    } catch {
      console.warn(`Impossible de lancer ${config.executeAfterSync}`);
    }
  }

  console.log("✅ Synchronisation terminée");
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(`❌ Erreur: ${e.message}`);
    Deno.exit(1);
  });
}
