import { ensureDir, exists } from "https://deno.land/std@0.208.0/fs/mod.ts";
import { walk } from "https://deno.land/std@0.208.0/fs/walk.ts";
import { join, relative, dirname } from "https://deno.land/std@0.208.0/path/mod.ts";
import { serve } from "https://deno.land/std@0.208.0/http/server.ts";

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
  const exeDir = dirname(Deno.execPath());
  const local = join(exeDir, "config.json");
  if (existsSync(local)) return local;
  return join(Deno.cwd(), "config.json");
}

function resolveSplashPath(): string {
  const exeDir = dirname(Deno.execPath());
  const local = join(exeDir, "web", "splash.html");
  if (existsSync(local)) return local;
  return join(Deno.cwd(), "web", "splash.html");
}

function existsSync(p: string): boolean {
  try {
    return Deno.statSync(p) != null;
  } catch {
    return false;
  }
}

function openBrowser(path: string) {
  const url = path.startsWith("http") ? path : `file://${path}`;
  const cmd =
    Deno.build.os === "windows"
      ? new Deno.Command("cmd", { args: ["/c", "start", "", url] })
      : Deno.build.os === "darwin"
      ? new Deno.Command("open", { args: [url] })
      : new Deno.Command("xdg-open", { args: [url] });
  cmd.spawn();
}

interface GuiServer {
  port: number;
  broadcast: (msg: unknown) => void;
  close: () => void;
}

function startGuiServer(): GuiServer {
  const clients = new Set<WebSocket>();
  const handler = (req: Request): Response => {
    const { socket, response } = Deno.upgradeWebSocket(req);
    clients.add(socket);
    socket.onclose = () => clients.delete(socket);
    socket.onerror = () => clients.delete(socket);
    return response;
  };

  const server = serve(handler, { port: 0 });
  const addr = server.listener.addr as Deno.NetAddr;
  const broadcast = (msg: unknown) => {
    const data = JSON.stringify(msg);
    for (const ws of clients) {
      try {
        ws.send(data);
      } catch {
        clients.delete(ws);
      }
    }
  };

  return { port: addr.port, broadcast, close: () => server.close() };
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

async function copyFileIfNeeded(file: string, config: Config): Promise<boolean> {
  const rel = relative(config.sourceDirectory, file);
  const dest = join(config.targetDirectory, rel);
  await ensureDir(dirname(dest));

  try {
    const srcInfo = await Deno.stat(file);
    const destExists = await exists(dest);
    if (destExists) {
      const destInfo = await Deno.stat(dest);
      if (destInfo.mtime?.getTime() === srcInfo.mtime?.getTime() && destInfo.size === srcInfo.size) {
        return false;
      }
    }
  } catch {
    // ignore comparison errors
  }

  await Deno.copyFile(file, dest);
  return true;
}

async function copyAllFiles(
  files: string[],
  config: Config,
  progress: (index: number, file: string, copied: number) => void,
): Promise<number> {
  const concurrency = config.parallelCopies ?? 1;
  let idx = 0;
  let copied = 0;

  async function worker() {
    while (true) {
      const i = idx++;
      if (i >= files.length) break;
      const f = files[i];
      const wasCopied = await copyFileIfNeeded(f, config);
      if (wasCopied) copied++;
      progress(i, f, copied);
    }
  }

  const workers: Promise<void>[] = [];
  for (let i = 0; i < concurrency; i++) workers.push(worker());
  await Promise.all(workers);
  return copied;
}

async function main() {
  const config = await loadConfig();
  await ensureDir(config.targetDirectory);

  const gui = startGuiServer();
  const splashPath = resolveSplashPath();
  openBrowser(`${splashPath}?ws=${gui.port}`);

  gui.broadcast({
    type: "app-info",
    appName: config.appName ?? "SyncOtter",
    appDescription: config.appDescription ?? "Synchronisation en cours",
    executeAfterSync: config.executeAfterSync,
  });

  const files = await scanSourceFiles(config);
  gui.broadcast({ type: "update-status", message: `📥 ${files.length} fichiers à synchroniser` });
  let copied = 0;
  const startTime = Date.now();

  await copyAllFiles(
    files,
    config,
    (i, file, count) => {
      copied = count;
      const progress = Math.round(((i + 1) / files.length) * 100);
      gui.broadcast({
        type: "update-progress",
        progress,
        detail: `${i + 1}/${files.length} • ${file}`,
        current: i + 1,
        total: files.length,
        fileName: file,
        copied: count,
      });
    },
  );

  if (config.executeAfterSync) {
    gui.broadcast({ type: "update-status", message: "🚀 Lancement de l'application" });
    try {
      const cmd = new Deno.Command(config.executeAfterSync, { args: [] });
      await cmd.spawn().status;
    } catch {
      gui.broadcast({ type: "update-status", message: `Impossible de lancer ${config.executeAfterSync}`, level: "warning" });
    }
  }

  gui.broadcast({ type: "update-status", message: "✅ Synchronisation terminée", level: "success" });
  const duration = Math.round((Date.now() - startTime) / 1000);
  gui.broadcast({ type: "telemetry-summary", duration, filesCopied: copied, errors: 0 });
  gui.close();
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(`❌ Erreur: ${e.message}`);
    Deno.exit(1);
  });
}
