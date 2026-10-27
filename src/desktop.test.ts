import type { Mock } from "bun:test";
import { afterEach, beforeEach, describe, expect, spyOn, test } from "bun:test";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import {
  buildScaledExec,
  extractCurrentScale,
  findAppById,
  listApplications,
  parseDesktopFile,
  resetAppScale,
  setAppScale,
  stripScalingFromExec,
} from "./desktop.ts";
import { extractCommandFromExec } from "./detector.ts";

const originalExec =
  'env TEST_MODE=desktop LABEL="Steam client" /nonexistent/steam -bigpicture -silent %U';

describe("Steam scaling commands", () => {
  test.each([1, 2])("generates only GDK_SCALE=%s without changing launch arguments", (scale) => {
    const exec = buildScaledExec(originalExec, scale, "GDK_SCALE");
    expect(exec).toBe(
      `env GDK_SCALE=${scale} TEST_MODE=desktop LABEL="Steam client" /nonexistent/steam -bigpicture -silent %U`,
    );
    expect(extractCommandFromExec(exec)).toEqual([
      "env",
      `GDK_SCALE=${scale}`,
      "TEST_MODE=desktop",
      "LABEL=Steam client",
      "/nonexistent/steam",
      "-bigpicture",
      "-silent",
    ]);
    expect(stripScalingFromExec(exec)).toBe(originalExec);
  });

  test.each([0, 1.25, 1.5, 2.5, 3, Number.NaN, Number.POSITIVE_INFINITY])(
    "rejects unsupported scale %s",
    (scale) => {
      expect(() => buildScaledExec("steam %U", scale, "GDK_SCALE")).toThrow("only 1× or 2×");
    },
  );

  test("replaces previous scaling markers instead of stacking them", () => {
    const exec = buildScaledExec(
      "env QT_SCALE_FACTOR=1.5 GDK_SCALE=2 GDK_DPI_SCALE=0.5 SLINT_SCALE_FACTOR=1.5 TEST_MODE=desktop steam -bigpicture %U",
      1,
      "GDK_SCALE",
    );
    expect(exec).toBe("env GDK_SCALE=1 TEST_MODE=desktop steam -bigpicture %U");
    expect(buildScaledExec(exec, 2, "GDK_SCALE")).toBe(
      "env GDK_SCALE=2 TEST_MODE=desktop steam -bigpicture %U",
    );
  });

  test("resetting a plain launch removes the now-unnecessary env wrapper", () => {
    const exec = buildScaledExec("steam -bigpicture %U", 2, "GDK_SCALE");
    expect(stripScalingFromExec(exec)).toBe("steam -bigpicture %U");
  });

  test("Steam reads GDK_SCALE ahead of unrelated toolkit markers", () => {
    const exec =
      "env SLINT_SCALE_FACTOR=1.5 QT_SCALE_FACTOR=1.75 GDK_DPI_SCALE=0.5 GDK_SCALE=2 steam %U";
    expect(extractCurrentScale(exec, "GDK_SCALE")).toEqual({
      scale: 2,
      detectedStrategy: "GDK_SCALE",
    });
    expect(extractCurrentScale("env GDK_DPI_SCALE=0.5 steam %U", "GDK_SCALE")).toEqual({
      scale: 1,
      detectedStrategy: "GDK_SCALE",
    });
  });

  test("generic GTK continues reading DPI scaling, not integer window scaling", () => {
    const exec = "env GDK_SCALE=2 GDK_DPI_SCALE=0.75 gtk-app %U";
    expect(extractCurrentScale(exec)).toEqual({ scale: 0.75, detectedStrategy: "GDK_DPI_SCALE" });
    expect(extractCurrentScale(exec, "GDK_DPI_SCALE")).toEqual({
      scale: 0.75,
      detectedStrategy: "GDK_DPI_SCALE",
    });
  });
});

describe("Steam desktop persistence", () => {
  let home: string;
  let desktopPath: string;
  let previousPath: string | undefined;
  let homeSpy: Mock<typeof os.homedir>;
  let existsSpy: Mock<typeof fs.existsSync>;
  const appId = "omarchy-steam-scale-test";

  beforeEach(() => {
    home = fs.mkdtempSync(path.join(os.tmpdir(), "omarchy-steam-scale-"));
    homeSpy = spyOn(os, "homedir").mockReturnValue(home);
    const existsSync = fs.existsSync.bind(fs);
    existsSpy = spyOn(fs, "existsSync").mockImplementation((file) => {
      if (file === "/usr/local/share/applications" || file === "/usr/share/applications")
        return false;
      return existsSync(file);
    });
    // External validation/database utilities are absent here; no applications run.
    previousPath = process.env.PATH;
    const bin = path.join(home, "bin");
    fs.mkdirSync(bin);
    process.env.PATH = bin;
    const applications = path.join(home, ".local/share/applications");
    fs.mkdirSync(applications, { recursive: true });
    desktopPath = path.join(applications, `${appId}.desktop`);
    fs.writeFileSync(
      desktopPath,
      `[Desktop Entry]\nType=Application\nName=Steam test\nExec=${originalExec}\nStartupWMClass=Steam\nCategories=Game;\n\n[Desktop Action BigPicture]\nName=Big Picture\nExec=steam -bigpicture\n`,
    );
  });

  afterEach(() => {
    if (previousPath === undefined) delete process.env.PATH;
    else process.env.PATH = previousPath;
    homeSpy.mockRestore();
    existsSpy.mockRestore();
    fs.rmSync(home, { recursive: true, force: true });
  });

  test.each([1, 2])("persists and reloads Steam scale %s with its own strategy", (scale) => {
    const app = setAppScale(appId, scale);
    expect(app.toolkit).toBe("steam");
    expect(app.strategy).toBe("GDK_SCALE");
    expect(app.currentScale).toBe(scale);
    expect(parseDesktopFile(desktopPath)?.exec).toBe(
      buildScaledExec(originalExec, scale, "GDK_SCALE"),
    );
    expect(findAppById(appId)?.currentScale).toBe(scale);
    expect(listApplications().find((candidate) => candidate.id === appId)).toMatchObject({
      toolkit: "steam",
      strategy: "GDK_SCALE",
      currentScale: scale,
    });
    expect(fs.readFileSync(desktopPath, "utf8")).toContain(
      "[Desktop Action BigPicture]\nName=Big Picture\nExec=steam -bigpicture",
    );
  });

  test("fractional sets cannot overwrite the desktop, even with a strategy override", () => {
    setAppScale(appId, 2);
    const before = fs.readFileSync(desktopPath, "utf8");
    for (const strategy of [
      undefined,
      "GDK_DPI_SCALE",
      "UNIVERSAL_FALLBACK",
      "QT_SCALE_FACTOR",
    ] as const) {
      expect(() => setAppScale(appId, 1.5, strategy)).toThrow("only 1× or 2×");
      expect(fs.readFileSync(desktopPath, "utf8")).toBe(before);
    }
  });

  test("Steam ignores an incompatible override and replaces fallback markers", () => {
    const content = fs
      .readFileSync(desktopPath, "utf8")
      .replace(
        originalExec,
        `env QT_SCALE_FACTOR=1.5 SLINT_SCALE_FACTOR=1.5 GDK_DPI_SCALE=0.5 GDK_SCALE=2 ${originalExec.slice(4)}`,
      );
    fs.writeFileSync(desktopPath, content);
    expect(findAppById(appId)).toMatchObject({ strategy: "GDK_SCALE", currentScale: 2 });
    expect(listApplications().find((candidate) => candidate.id === appId)).toMatchObject({
      strategy: "GDK_SCALE",
      currentScale: 2,
    });
    const app = setAppScale(appId, 1, "UNIVERSAL_FALLBACK");
    expect(app.strategy).toBe("GDK_SCALE");
    expect(app.currentScale).toBe(1);
    expect(app.exec).toBe(buildScaledExec(originalExec, 1, "GDK_SCALE"));
  });

  test("replacing then resetting restores the original environment and launch behavior", () => {
    const originalContent = fs.readFileSync(desktopPath, "utf8");
    setAppScale(appId, 2);
    setAppScale(appId, 1);
    expect(resetAppScale(appId).success).toBe(true);
    expect(fs.readFileSync(desktopPath, "utf8")).toBe(originalContent);
    expect(findAppById(appId)).toMatchObject({
      strategy: "GDK_SCALE",
      currentScale: 1,
      exec: originalExec,
    });
  });
});
