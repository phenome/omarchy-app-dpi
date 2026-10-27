import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { spawnSync } from "node:child_process";
import { copyFile, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { prepare } from "./release-version.js";

const packageMetadata = {
  name: "release-fixture",
  version: "1.0.0",
  private: true,
  scripts: { start: "bun src/cli.ts" },
};
const manifestMetadata = {
  id: "release-fixture",
  version: "1.0.0",
  name: "Release fixture",
  permissions: ["read"],
};

describe("release metadata preparation", () => {
  let cwd: string;

  beforeEach(async () => {
    cwd = await mkdtemp(join(tmpdir(), "release-version-"));
    await writeFile(join(cwd, "package.json"), JSON.stringify(packageMetadata));
    await copyFile(new URL("../biome.json", import.meta.url), join(cwd, "biome.json"));
    await copyFile(new URL("../.gitignore", import.meta.url), join(cwd, ".gitignore"));
  });

  afterEach(async () => {
    await rm(cwd, { recursive: true, force: true });
  });

  test("updates both versions while preserving unrelated metadata", async () => {
    await writeFile(join(cwd, "manifest.json"), JSON.stringify(manifestMetadata));
    const lock = '{ "workspaces": { "": { "name": "release-fixture" } } }\n';
    await writeFile(join(cwd, "bun.lock"), lock);
    const version = "7.8.9-beta.4";

    await prepare({}, { cwd, nextRelease: { version } });

    expect(JSON.parse(await readFile(join(cwd, "package.json"), "utf8"))).toEqual({
      ...packageMetadata,
      version,
    });
    expect(JSON.parse(await readFile(join(cwd, "manifest.json"), "utf8"))).toEqual({
      ...manifestMetadata,
      version,
    });
    expect(await readFile(join(cwd, "bun.lock"), "utf8")).toBe(lock);
    const check = spawnSync(
      process.execPath,
      [
        fileURLToPath(import.meta.resolve("@biomejs/biome/bin/biome")),
        "check",
        "package.json",
        "manifest.json",
      ],
      { cwd, encoding: "utf8" },
    );
    expect(check.status).toBe(0);
  });

  test.each(["malformed", "missing"])(
    "rejects a %s manifest without changing package metadata",
    async (failure) => {
      if (failure === "malformed") {
        await writeFile(join(cwd, "manifest.json"), "{ malformed JSON");
      }
      const originalPackage = await readFile(join(cwd, "package.json"), "utf8");

      await expect(prepare({}, { cwd, nextRelease: { version: "2.3.4" } })).rejects.toThrow();

      expect(await readFile(join(cwd, "package.json"), "utf8")).toBe(originalPackage);
    },
  );
});
