import { execFileSync } from "node:child_process";
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Synchronize release metadata before semantic-release commits it.
 * @param {unknown} _pluginConfig
 * @param {{ cwd: string, nextRelease: { version: string } }} context
 */
export async function prepare(_pluginConfig, context) {
  const packagePath = join(context.cwd, "package.json");
  const manifestPath = join(context.cwd, "manifest.json");
  const packageData = JSON.parse(await readFile(packagePath, "utf8"));
  const manifestData = JSON.parse(await readFile(manifestPath, "utf8"));

  packageData.version = context.nextRelease.version;
  manifestData.version = context.nextRelease.version;

  await writeFile(packagePath, `${JSON.stringify(packageData, null, 2)}\n`);
  await writeFile(manifestPath, `${JSON.stringify(manifestData, null, 2)}\n`);
  execFileSync(
    process.execPath,
    [
      fileURLToPath(import.meta.resolve("@biomejs/biome/bin/biome")),
      "format",
      "--write",
      packagePath,
      manifestPath,
    ],
    { cwd: context.cwd, stdio: "inherit" },
  );
}
