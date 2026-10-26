import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { detectToolkit, resolveBinary } from "./detector.ts";
import type { AppInfo, ScalingStrategy } from "./types.ts";

export function getApplicationDirs(): { user: string; system: string[] } {
  const home = os.homedir();
  const user = path.join(home, ".local/share/applications");
  const system = ["/usr/local/share/applications", "/usr/share/applications"];
  return { user, system };
}

export function parseDesktopFile(filePath: string): {
  id: string;
  name: string;
  exec: string;
  icon: string;
  comment?: string;
  terminal?: boolean;
  noDisplay?: boolean;
  type?: string;
  startupWMClass?: string;
  categories?: string;
} | null {
  try {
    const content = fs.readFileSync(filePath, "utf8");
    const lines = content.split("\n");
    let inDesktopEntry = false;
    let name = "";
    let exec = "";
    let icon = "";
    let comment: string | undefined;
    let terminal: boolean | undefined;
    let noDisplay: boolean | undefined;
    let type: string | undefined;
    let startupWMClass: string | undefined;
    let categories: string | undefined;

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (line.startsWith("[") && line.endsWith("]")) {
        inDesktopEntry = line === "[Desktop Entry]";
        continue;
      }
      if (!inDesktopEntry || line.startsWith("#") || !line.includes("=")) {
        continue;
      }

      const eqIdx = line.indexOf("=");
      const key = line.slice(0, eqIdx).trim();
      const val = line.slice(eqIdx + 1).trim();

      if (key === "Name" && !name) {
        name = val;
      } else if (key === "Exec" && !exec) {
        exec = val;
      } else if (key === "Icon" && !icon) {
        icon = val;
      } else if (key === "Comment" && !comment) {
        comment = val;
      } else if (key === "Terminal") {
        terminal = val.toLowerCase() === "true";
      } else if (key === "NoDisplay") {
        noDisplay = val.toLowerCase() === "true";
      } else if (key === "Type") {
        type = val;
      } else if (key === "StartupWMClass" && !startupWMClass) {
        startupWMClass = val;
      } else if (key === "Categories" && !categories) {
        categories = val;
      }
    }

    if (!name || !exec) return null;

    const id = path.basename(filePath, ".desktop");

    return {
      id,
      name,
      exec,
      icon: icon || id,
      comment,
      terminal,
      noDisplay,
      type,
      startupWMClass,
      categories,
    };
  } catch {
    return null;
  }
}

export function extractCurrentScale(execLine: string): {
  scale: number;
  detectedStrategy?: ScalingStrategy;
} {
  // Check Slint
  const slintMatch = execLine.match(/SLINT_SCALE_FACTOR=([0-9.]+)/);
  if (slintMatch?.[1]) {
    const val = parseFloat(slintMatch[1]);
    if (!Number.isNaN(val) && val > 0) {
      return { scale: val, detectedStrategy: "SLINT_SCALE_FACTOR" };
    }
  }

  // Check Qt
  const qtMatch = execLine.match(/QT_SCALE_FACTOR=([0-9.]+)/);
  if (qtMatch?.[1]) {
    const val = parseFloat(qtMatch[1]);
    if (!Number.isNaN(val) && val > 0) {
      return { scale: val, detectedStrategy: "QT_SCALE_FACTOR" };
    }
  }

  // Check GTK
  const gtkMatch = execLine.match(/GDK_DPI_SCALE=([0-9.]+)/);
  if (gtkMatch?.[1]) {
    const val = parseFloat(gtkMatch[1]);
    if (!Number.isNaN(val) && val > 0) {
      return { scale: val, detectedStrategy: "GDK_DPI_SCALE" };
    }
  }

  // Check Chromium / Electron
  const chromeMatch = execLine.match(/--force-device-scale-factor=([0-9.]+)/);
  if (chromeMatch?.[1]) {
    const val = parseFloat(chromeMatch[1]);
    if (!Number.isNaN(val) && val > 0) {
      return { scale: val, detectedStrategy: "CHROME_SCALE_FLAG" };
    }
  }

  // Check Java
  const javaMatch = execLine.match(/-Dsun\.java2d\.uiScale=([0-9.]+)/);
  if (javaMatch?.[1]) {
    const val = parseFloat(javaMatch[1]);
    if (!Number.isNaN(val) && val > 0) {
      return { scale: val, detectedStrategy: "JAVA_UI_SCALE" };
    }
  }

  return { scale: 1.0 };
}
export function getLauncherHides(): Set<string> {
  const hides = new Set<string>();
  const paths = [
    "/usr/share/omarchy/default/omarchy/launcher.hides",
    path.join(os.homedir(), ".config/omarchy/launcher.hides"),
  ];
  for (const p of paths) {
    if (fs.existsSync(p)) {
      try {
        const lines = fs.readFileSync(p, "utf8").split("\n");
        for (const line of lines) {
          const trimmed = line.trim();
          if (trimmed && !trimmed.startsWith("#")) {
            hides.add(trimmed.endsWith(".desktop") ? trimmed.slice(0, -8) : trimmed);
          }
        }
      } catch {
        // Ignore read error
      }
    }
  }
  return hides;
}

export function listApplications(): AppInfo[] {
  const { user, system } = getApplicationDirs();
  const appMap = new Map<string, { activePath: string; systemPath: string | null }>();

  // Helper to scan directory
  const scanDir = (dir: string, isUser: boolean) => {
    if (!fs.existsSync(dir)) return;
    const entries = fs.readdirSync(dir);
    for (const entry of entries) {
      if (!entry.endsWith(".desktop")) continue;
      const fullPath = path.join(dir, entry);
      const id = entry.slice(0, -".desktop".length);

      const existing = appMap.get(id);
      if (!existing) {
        appMap.set(id, {
          activePath: fullPath,
          systemPath: isUser ? null : fullPath,
        });
      } else {
        if (!isUser && !existing.systemPath) {
          existing.systemPath = fullPath;
        }
      }
    }
  };

  // User dir first so it takes precedence as active
  scanDir(user, true);
  for (const sysDir of system) {
    scanDir(sysDir, false);
  }
  const launcherHides = getLauncherHides();
  const results: AppInfo[] = [];

  for (const [id, paths] of appMap.entries()) {
    if (launcherHides.has(id)) continue;
    const parsed = parseDesktopFile(paths.activePath);
    if (!parsed) continue;
    if (parsed.type && parsed.type !== "Application") continue;
    if (parsed.noDisplay) continue;
    if (parsed.terminal) continue;

    const { scale, detectedStrategy } = extractCurrentScale(parsed.exec);
    const resolved = resolveBinary(parsed.exec);
    const { toolkit, strategy: detectedFromBinary } = detectToolkit(resolved, {
      execLine: parsed.exec,
      startupWMClass: parsed.startupWMClass,
      categories: parsed.categories,
    });

    const isOverridden = scale !== 1.0;

    results.push({
      id,
      name: parsed.name,
      icon: parsed.icon,
      exec: parsed.exec,
      resolvedBinary: resolved,
      toolkit,
      strategy: detectedStrategy || detectedFromBinary,
      currentScale: scale,
      isOverridden,
      desktopPath: paths.activePath,
      systemDesktopPath: paths.systemPath,
      comment: parsed.comment,
      terminal: parsed.terminal,
      noDisplay: parsed.noDisplay,
    });
  }

  results.sort((a, b) => a.name.localeCompare(b.name));
  return results;
}

export function findAppById(appId: string): AppInfo | null {
  const normId = appId.endsWith(".desktop") ? appId.slice(0, -".desktop".length) : appId;

  // Search by exact desktop file in user or system first for speed
  const { user, system } = getApplicationDirs();
  const candidates = [
    path.join(user, `${normId}.desktop`),
    ...system.map((s) => path.join(s, `${normId}.desktop`)),
  ];

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      const parsed = parseDesktopFile(candidate);
      if (parsed) {
        const { scale, detectedStrategy } = extractCurrentScale(parsed.exec);
        const resolved = resolveBinary(parsed.exec);
        const { toolkit, strategy } = detectToolkit(resolved, {
          execLine: parsed.exec,
          startupWMClass: parsed.startupWMClass,
          categories: parsed.categories,
        });
        return {
          id: parsed.id,
          name: parsed.name,
          icon: parsed.icon,
          exec: parsed.exec,
          resolvedBinary: resolved,
          toolkit,
          strategy: detectedStrategy || strategy,
          currentScale: scale,
          isOverridden: scale !== 1.0,
          desktopPath: candidate,
          systemDesktopPath: candidate.startsWith(user)
            ? system.map((s) => path.join(s, `${normId}.desktop`)).find((p) => fs.existsSync(p)) ||
              null
            : candidate,
          comment: parsed.comment,
          terminal: parsed.terminal,
        };
      }
    }
  }

  // Fallback to scanning all if not found by exact filename
  const all = listApplications();
  return all.find((a) => a.id === normId || a.id.toLowerCase() === normId.toLowerCase()) || null;
}

export function stripScalingFromExec(execLine: string): string {
  let cleaned = execLine
    .replace(/\bSLINT_SCALE_FACTOR=[0-9.]+\s*/g, "")
    .replace(/\bQT_SCALE_FACTOR=[0-9.]+\s*/g, "")
    .replace(/\bGDK_SCALE=[0-9.]+\s*/g, "")
    .replace(/\bGDK_DPI_SCALE=[0-9.]+\s*/g, "")
    .replace(/--force-device-scale-factor=[0-9.]+\s*/g, "")
    .replace(/-Dsun\.java2d\.uiScale=[0-9.]+\s*/g, "")
    .trim();

  // If Exec=env (with no remaining env vars), remove the env prefix
  cleaned = cleaned.replace(/^env\s+/, "");
  return cleaned;
}

export function buildScaledExec(
  originalExec: string,
  scale: number,
  strategy: ScalingStrategy,
): string {
  const baseExec = stripScalingFromExec(originalExec);
  const scaleStr = scale.toFixed(2).replace(/\.?0+$/, (match) => (match === ".00" ? ".0" : match));

  switch (strategy) {
    case "SLINT_SCALE_FACTOR": {
      if (baseExec.startsWith("env ")) {
        return `env SLINT_SCALE_FACTOR=${scaleStr} ${baseExec.slice(4).trim()}`;
      }
      return `env SLINT_SCALE_FACTOR=${scaleStr} ${baseExec}`;
    }
    case "QT_SCALE_FACTOR": {
      if (baseExec.startsWith("env ")) {
        return `env QT_SCALE_FACTOR=${scaleStr} ${baseExec.slice(4).trim()}`;
      }
      return `env QT_SCALE_FACTOR=${scaleStr} ${baseExec}`;
    }
    case "GDK_DPI_SCALE": {
      if (baseExec.startsWith("env ")) {
        return `env GDK_SCALE=1 GDK_DPI_SCALE=${scaleStr} ${baseExec.slice(4).trim()}`;
      }
      return `env GDK_SCALE=1 GDK_DPI_SCALE=${scaleStr} ${baseExec}`;
    }
    case "CHROME_SCALE_FLAG": {
      const flag = `--force-device-scale-factor=${scaleStr}`;
      // Insert flag before field codes like %U, %u, %f, %F, or at end
      const fieldCodeMatch = baseExec.match(/\s+(%[a-zA-Z])(?:\s+|$)/);
      if (fieldCodeMatch && fieldCodeMatch.index !== undefined) {
        const idx = fieldCodeMatch.index;
        return `${baseExec.slice(0, idx)} ${flag}${baseExec.slice(idx)}`;
      }
      return `${baseExec} ${flag}`;
    }
    case "JAVA_UI_SCALE": {
      const flag = `-Dsun.java2d.uiScale=${scaleStr}`;
      // Insert right after java executable
      if (baseExec.startsWith("java ")) {
        return `java ${flag} ${baseExec.slice(5).trim()}`;
      }
      return `${baseExec} ${flag}`;
    }
    default: {
      // Fallback for UNKNOWN: provide generic env wrappers
      return `env QT_SCALE_FACTOR=${scaleStr} GDK_SCALE=1 GDK_DPI_SCALE=${scaleStr} SLINT_SCALE_FACTOR=${scaleStr} ${baseExec}`;
    }
  }
}

export function setAppScale(
  appId: string,
  scale: number,
  strategyOverride?: ScalingStrategy,
): AppInfo {
  const app = findAppById(appId);
  if (!app) {
    throw new Error(`Application '${appId}' not found in desktop database.`);
  }

  if (app.strategy === "BROWSER_ZOOM") {
    throw new Error(
      `'${app.name}' is a WebApp running in the browser. Scale it directly in the window using Ctrl++, Ctrl+-, or Ctrl+0.`,
    );
  }
  if (app.strategy === "IN_GAME_SETTINGS") {
    throw new Error(
      `'${app.name}' is a 3D game. Configure resolution and scaling in its in-game graphics settings.`,
    );
  }

  const { user } = getApplicationDirs();
  if (!fs.existsSync(user)) {
    fs.mkdirSync(user, { recursive: true });
  }

  const userDesktopPath = path.join(user, `${app.id}.desktop`);

  // Read content from current user file or system file
  const sourcePath = fs.existsSync(userDesktopPath) ? userDesktopPath : app.desktopPath;
  const content = fs.readFileSync(sourcePath, "utf8");

  const strategy =
    strategyOverride && strategyOverride !== "UNKNOWN" ? strategyOverride : app.strategy;
  const newExec = buildScaledExec(app.exec, scale, strategy);

  const lines = content.split("\n");
  let inDesktopEntry = false;
  let execReplaced = false;
  const newLines: string[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.startsWith("[") && line.endsWith("]")) {
      inDesktopEntry = line === "[Desktop Entry]";
      newLines.push(rawLine);
      continue;
    }
    if (inDesktopEntry && line.startsWith("Exec=")) {
      newLines.push(`Exec=${newExec}`);
      execReplaced = true;
      continue;
    }
    newLines.push(rawLine);
  }

  if (!execReplaced) {
    throw new Error(`Failed to find Exec= line in ${sourcePath}`);
  }

  const newContent = newLines.join("\n");
  const tempPath = `${userDesktopPath}.${Date.now()}.desktop`;
  fs.writeFileSync(tempPath, newContent, "utf8");

  // Validate with desktop-file-validate, tolerating preexisting vendor quirks
  let valid = true;
  try {
    execFileSync("desktop-file-validate", [tempPath], { stdio: "ignore" });
  } catch {
    // If source file also failed validation, tolerate preexisting vendor quirks
    try {
      execFileSync("desktop-file-validate", [sourcePath], { stdio: "ignore" });
      valid = false;
    } catch {
      valid = true;
    }
  }

  if (!valid) {
    if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    throw new Error(`Generated desktop file failed validation for '${app.id}'.`);
  }

  fs.renameSync(tempPath, userDesktopPath);
  // Update desktop database
  try {
    execFileSync("update-desktop-database", [user], { stdio: "ignore" });
  } catch {
    // Non-fatal if update-desktop-database fails
  }

  const updated = findAppById(app.id);
  if (!updated) {
    throw new Error(`Failed to reload application info for '${app.id}'.`);
  }
  return updated;
}

export function resetAppScale(appId: string): { success: boolean; message: string } {
  const app = findAppById(appId);
  if (!app) {
    throw new Error(`Application '${appId}' not found.`);
  }

  const { user } = getApplicationDirs();
  const userDesktopPath = path.join(user, `${app.id}.desktop`);

  if (!fs.existsSync(userDesktopPath)) {
    return { success: true, message: `Application '${app.id}' has no custom override.` };
  }

  // If there's a system desktop file, check if removing the user file restores default cleanly
  if (app.systemDesktopPath && fs.existsSync(app.systemDesktopPath)) {
    const userContent = fs.readFileSync(userDesktopPath, "utf8");
    const systemContent = fs.readFileSync(app.systemDesktopPath, "utf8");

    const cleanedUser = stripScalingFromExec(userContent);
    const cleanedSystem = stripScalingFromExec(systemContent);

    // If only the scaling differed, we can safely delete the user copy
    if (cleanedUser === cleanedSystem) {
      fs.unlinkSync(userDesktopPath);
      try {
        execFileSync("update-desktop-database", [user], { stdio: "ignore" });
      } catch {
        // Ignore
      }
      return {
        success: true,
        message: `Removed user override for '${app.id}'. Reverted to system defaults.`,
      };
    }
  }

  // Otherwise, strip the scaling in place from the user file
  const content = fs.readFileSync(userDesktopPath, "utf8");
  const lines = content.split("\n");
  let inDesktopEntry = false;
  const newLines: string[] = [];

  for (const rawLine of lines) {
    const line = rawLine.trim();
    if (line.startsWith("[") && line.endsWith("]")) {
      inDesktopEntry = line === "[Desktop Entry]";
      newLines.push(rawLine);
      continue;
    }
    if (inDesktopEntry && line.startsWith("Exec=")) {
      const orig = line.slice("Exec=".length);
      const cleaned = stripScalingFromExec(orig);
      newLines.push(`Exec=${cleaned}`);
      continue;
    }
    newLines.push(rawLine);
  }

  const tempPath = `${userDesktopPath}.${Date.now()}.desktop`;
  fs.writeFileSync(tempPath, newLines.join("\n"), "utf8");
  let valid = true;
  try {
    execFileSync("desktop-file-validate", [tempPath], { stdio: "ignore" });
  } catch {
    try {
      if (app.systemDesktopPath) {
        execFileSync("desktop-file-validate", [app.systemDesktopPath], { stdio: "ignore" });
        valid = false;
      }
    } catch {
      valid = true;
    }
  }

  if (!valid) {
    if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
    throw new Error(`Failed to validate reset desktop file for '${app.id}'.`);
  }
  fs.renameSync(tempPath, userDesktopPath);
  try {
    execFileSync("update-desktop-database", [user], { stdio: "ignore" });
  } catch {
    // Ignore
  }

  return {
    success: true,
    message: `Restored default scaling for '${app.id}'.`,
  };
}
