import { execFileSync } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import type { ScalingStrategy, ToolkitType } from "./types.ts";

export function extractCommandFromExec(execLine: string): string[] {
  // Strip freedesktop field codes: %f, %F, %u, %U, %d, %D, %n, %N, %i, %c, %k, %v, %m
  const sanitized = execLine.replace(/%[a-zA-Z]/g, "").trim();

  // Basic shell-like tokenization supporting single and double quotes
  const tokens: string[] = [];
  let current = "";
  let inDouble = false;
  let inSingle = false;
  let escaped = false;

  for (let i = 0; i < sanitized.length; i++) {
    const char = sanitized[i];
    if (!char) continue;
    if (escaped) {
      current += char;
      escaped = false;
      continue;
    }
    if (char === "\\") {
      escaped = true;
      continue;
    }
    if (char === '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (char === "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (/\s/.test(char) && !inDouble && !inSingle) {
      if (current.length > 0) {
        tokens.push(current);
        current = "";
      }
      continue;
    }
    current += char;
  }
  if (current.length > 0) {
    tokens.push(current);
  }

  return tokens;
}

export function findExecutableInPath(command: string): string | null {
  if (command.includes("/")) {
    if (fs.existsSync(command)) {
      return path.resolve(command);
    }
    return null;
  }

  const pathEnv = process.env.PATH || "/usr/bin:/bin";
  const dirs = pathEnv.split(":");
  for (const dir of dirs) {
    const full = path.join(dir, command);
    if (fs.existsSync(full)) {
      try {
        fs.accessSync(full, fs.constants.X_OK);
        return full;
      } catch {
        // Not executable
      }
    }
  }
  return null;
}

export function resolveBinary(execLine: string, maxDepth = 5): string | null {
  const tokens = extractCommandFromExec(execLine);
  if (tokens.length === 0) return null;

  // Skip leading env or VAR=VALUE
  let cmdIndex = 0;
  if (tokens[0] === "env") {
    cmdIndex = 1;
  }
  while (cmdIndex < tokens.length) {
    const token = tokens[cmdIndex];
    if (token?.includes("=") && !token.startsWith("-") && !token.includes("/")) {
      cmdIndex++;
    } else {
      break;
    }
  }

  const cmd = tokens[cmdIndex];
  if (!cmd) return null;

  let currentPath = findExecutableInPath(cmd);
  if (!currentPath) return null;

  try {
    currentPath = fs.realpathSync(currentPath);
  } catch {
    return currentPath;
  }

  // Unwrap shell script wrappers up to maxDepth
  let depth = 0;
  while (depth < maxDepth) {
    depth++;
    try {
      const stat = fs.statSync(currentPath);
      if (!stat.isFile()) break;

      const fd = fs.openSync(currentPath, "r");
      const buffer = Buffer.alloc(65536);
      const bytesRead = fs.readSync(fd, buffer, 0, 65536, 0);
      fs.closeSync(fd);

      // Check if it's an ELF binary
      if (bytesRead >= 4 && buffer[0] === 0x7f && buffer.toString("ascii", 1, 4) === "ELF") {
        return currentPath;
      }

      // Check if it's a script (e.g. #!/bin/bash or #!/bin/sh)
      const content = buffer.toString("utf8", 0, bytesRead);
      if (content.startsWith("#!")) {
        const scriptDir = path.dirname(currentPath);
        const execMatches = [
          ...content.matchAll(
            /(?:^|\n)\s*exec\s+(?:-[a-zA-Z0-9_-]+\s+\S+\s+)?(?:["']?)([^"'\s\n;]+)/g,
          ),
        ];

        let nextFound = false;
        // Iterate in reverse (the final launch exec is almost always near the end)
        for (let i = execMatches.length - 1; i >= 0; i--) {
          const match = execMatches[i];
          if (!match?.[1]) continue;
          let target = match[1];
          if (target.startsWith("<") || target.startsWith(">") || target.startsWith("2>")) {
            continue;
          }
          target = target.replace(/\$(?:HERE|app_dir|DIR|APPDIR)\b/g, scriptDir);
          target = target.replace(/\$\{XDG_CONFIG_HOME:[^}]+\}/g, "");

          if (target.startsWith("/")) {
            if (fs.existsSync(target)) {
              currentPath = fs.realpathSync(target);
              nextFound = true;
              break;
            }
          } else {
            const resolvedRel = path.resolve(scriptDir, target);
            if (fs.existsSync(resolvedRel)) {
              currentPath = fs.realpathSync(resolvedRel);
              nextFound = true;
              break;
            }
            const inPath = findExecutableInPath(target);
            if (inPath && inPath !== currentPath) {
              currentPath = fs.realpathSync(inPath);
              nextFound = true;
              break;
            }
          }
        }
        if (nextFound) continue;
      }
      break;
    } catch {
      break;
    }
  }

  return currentPath;
}

interface CacheEntry {
  mtime: number;
  toolkit: ToolkitType;
  strategy: ScalingStrategy;
}

let memoryCache: Record<string, CacheEntry> | null = null;
const cachePath = path.join(
  process.env.XDG_CACHE_HOME || path.join(process.env.HOME || "", ".cache"),
  "omarchy-app-dpi",
  "cache.json",
);

function loadCache(): Record<string, CacheEntry> {
  if (memoryCache) return memoryCache;
  try {
    if (fs.existsSync(cachePath)) {
      memoryCache = JSON.parse(fs.readFileSync(cachePath, "utf8"));
      return memoryCache || {};
    }
  } catch {
    // Ignore corrupted cache
  }
  memoryCache = {};
  return memoryCache;
}

function saveCache(): void {
  if (!memoryCache) return;
  try {
    const dir = path.dirname(cachePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(cachePath, JSON.stringify(memoryCache), "utf8");
  } catch {
    // Ignore write failure
  }
}

export interface DetectionContext {
  execLine?: string;
  startupWMClass?: string;
  categories?: string;
}

export function detectToolkit(
  binaryPath: string | null,
  context?: DetectionContext,
): {
  toolkit: ToolkitType;
  strategy: ScalingStrategy;
} {
  // Check context signatures first (WebApps, PWAs, Games)
  if (context?.execLine) {
    const exec = context.execLine;
    if (
      exec.includes("omarchy-launch-webapp") ||
      exec.includes("--app=") ||
      context.startupWMClass?.toLowerCase().startsWith("chrome-")
    ) {
      return { toolkit: "webapp", strategy: "CHROME_SCALE_FLAG" };
    }
    if (exec.includes("steam steam://") || context.categories?.includes("Game;")) {
      return { toolkit: "game", strategy: "UNKNOWN" };
    }
  }

  if (!binaryPath || !fs.existsSync(binaryPath)) {
    return { toolkit: "unknown", strategy: "UNKNOWN" };
  }

  let mtime = 0;
  try {
    mtime = fs.statSync(binaryPath).mtimeMs;
    const cache = loadCache();
    const cached = cache[binaryPath];
    if (cached && cached.mtime === mtime) {
      return { toolkit: cached.toolkit, strategy: cached.strategy };
    }
  } catch {
    // stat failed
  }

  const result = detectToolkitUncached(binaryPath);

  if (mtime > 0) {
    const cache = loadCache();
    cache[binaryPath] = {
      mtime,
      toolkit: result.toolkit,
      strategy: result.strategy,
    };
    saveCache();
  }

  return result;
}

function detectToolkitUncached(binaryPath: string): {
  toolkit: ToolkitType;
  strategy: ScalingStrategy;
} {
  const binaryDir = path.dirname(binaryPath);
  const binaryName = path.basename(binaryPath).toLowerCase();
  // 1. Check Electron / Chromium file hierarchy signatures
  if (
    fs.existsSync(path.join(binaryDir, "resources/app.asar")) ||
    fs.existsSync(path.join(binaryDir, "resources.pak")) ||
    fs.existsSync(path.join(binaryDir, "chrome-flags.conf")) ||
    binaryName === "chrome" ||
    binaryName === "google-chrome" ||
    binaryName === "chromium" ||
    binaryName === "brave" ||
    binaryName === "electron" ||
    binaryName === "code" ||
    binaryName === "slack"
  ) {
    return { toolkit: "electron", strategy: "CHROME_SCALE_FLAG" };
  }

  // 2. Check Java
  if (binaryName === "java" || binaryName.endsWith("-java")) {
    return { toolkit: "java", strategy: "JAVA_UI_SCALE" };
  }

  // 3. Inspect ELF Dynamic Section using readelf
  let readelfOutput = "";
  try {
    readelfOutput = execFileSync("readelf", ["-d", binaryPath], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
    });
  } catch {
    // readelf failed or not an ELF file
  }

  if (readelfOutput) {
    if (readelfOutput.includes("libQt6Core.so")) {
      return { toolkit: "qt6", strategy: "QT_SCALE_FACTOR" };
    }
    if (readelfOutput.includes("libQt5Core.so")) {
      return { toolkit: "qt5", strategy: "QT_SCALE_FACTOR" };
    }
    if (readelfOutput.includes("libgtk-4.so")) {
      return { toolkit: "gtk4", strategy: "GDK_DPI_SCALE" };
    }
    if (readelfOutput.includes("libgtk-3.so")) {
      return { toolkit: "gtk3", strategy: "GDK_DPI_SCALE" };
    }
    if (readelfOutput.includes("libxul.so")) {
      return { toolkit: "gecko", strategy: "UNKNOWN" };
    }
    if (readelfOutput.includes("libjvm.so")) {
      return { toolkit: "java", strategy: "JAVA_UI_SCALE" };
    }
  }

  // 4. Check Slint signatures
  // Slint applications are typically static Rust binaries containing slint_core / SLINT_SCALE_FACTOR
  try {
    const hasSlint = execFileSync(
      "sh",
      [
        "-c",
        `strings "${binaryPath}" | grep -m 1 -E "SLINT_SCALE_FACTOR|slint_core|slint::|i_slint_core"`,
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    );
    if (hasSlint.trim().length > 0) {
      return { toolkit: "slint", strategy: "SLINT_SCALE_FACTOR" };
    }
  } catch {
    // grep returns non-zero when not matched
  }

  // 5. Check Electron/Chromium in binary
  try {
    const hasChrome = execFileSync(
      "sh",
      [
        "-c",
        `strings "${binaryPath}" | grep -m 1 -E "force-device-scale-factor|Chrome_RenderWidgetHost"`,
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    );
    if (hasChrome.trim().length > 0) {
      return { toolkit: "electron", strategy: "CHROME_SCALE_FLAG" };
    }
  } catch {
    // grep returns non-zero when not matched
  }

  // 5. Check Gecko by name
  if (binaryName === "firefox" || binaryName === "thunderbird") {
    return { toolkit: "gecko", strategy: "UNKNOWN" };
  }

  return { toolkit: "unknown", strategy: "UNKNOWN" };
}
