import process from "node:process";
import { findAppById, listApplications, resetAppScale, setAppScale } from "./desktop.ts";
import type { ScalingStrategy } from "./types.ts";

function printHelp(): void {
  console.log(`omarchy-app-scaling - Per-application scaling manager for Omarchy

Usage:
  omarchy-app-scaling list [--json] [--search <term>]
  omarchy-app-scaling inspect <app-id> [--json]
  omarchy-app-scaling set <app-id> <scale> [--strategy <strategy>] [--json]
  omarchy-app-scaling reset <app-id> [--json]
  omarchy-app-scaling --help

Aliases: omarchy-app-dpi

Examples:
  omarchy-app-scaling list --json
  omarchy-app-scaling inspect com.flectar.mail
  omarchy-app-scaling set com.flectar.mail 0.85
  omarchy-app-scaling set google-chrome 1.15
  omarchy-app-scaling reset com.flectar.mail
`);
}

export function main(): void {
  const args = process.argv.slice(2);
  if (args.length === 0 || args.includes("-h") || args.includes("--help")) {
    printHelp();
    process.exit(0);
  }

  const command = args[0];
  const isJson = args.includes("--json");

  try {
    switch (command) {
      case "list": {
        const searchIdx = args.indexOf("--search");
        const searchTerm = searchIdx !== -1 ? args[searchIdx + 1]?.toLowerCase() : null;

        let apps = listApplications();
        if (searchTerm) {
          apps = apps.filter(
            (a) =>
              a.name.toLowerCase().includes(searchTerm) ||
              a.id.toLowerCase().includes(searchTerm) ||
              a.comment?.toLowerCase().includes(searchTerm),
          );
        }

        if (isJson) {
          console.log(JSON.stringify(apps, null, 2));
        } else {
          console.log(`Found ${apps.length} applications:\n`);
          for (const app of apps) {
            const scaleTag = app.currentScale !== 1.0 ? ` [${app.currentScale}x]` : "";
            const overrideTag = app.isOverridden ? " (custom)" : "";
            console.log(
              `  • ${app.name} (${app.id})${scaleTag}${overrideTag} [${app.toolkit.toUpperCase()}]`,
            );
          }
        }
        break;
      }

      case "inspect": {
        const appId = args[1];
        if (!appId) {
          console.error("Error: missing <app-id>");
          process.exit(1);
        }

        const app = findAppById(appId);
        if (!app) {
          console.error(`Error: application '${appId}' not found.`);
          process.exit(1);
        }

        if (isJson) {
          console.log(JSON.stringify(app, null, 2));
        } else {
          console.log(`Application: ${app.name}`);
          console.log(`  ID:              ${app.id}`);
          console.log(`  Icon:            ${app.icon}`);
          console.log(`  Toolkit:         ${app.toolkit}`);
          console.log(`  Strategy:        ${app.strategy}`);
          console.log(`  Current Scale:   ${app.currentScale}x`);
          console.log(`  Is Overridden:   ${app.isOverridden}`);
          console.log(`  Desktop File:    ${app.desktopPath}`);
          console.log(`  Resolved Binary: ${app.resolvedBinary || "(unresolved)"}`);
          console.log(`  Exec Line:       ${app.exec}`);
        }
        break;
      }

      case "set": {
        const appId = args[1];
        const scaleRaw = args[2];
        if (!appId || !scaleRaw) {
          console.error(
            "Usage: omarchy-app-dpi set <app-id> <scale> [--strategy <strategy>] [--json]",
          );
          process.exit(1);
        }

        const scale = parseFloat(scaleRaw);
        if (Number.isNaN(scale) || scale <= 0 || scale > 5) {
          console.error(`Error: invalid scale factor '${scaleRaw}'. Must be between 0.1 and 5.0.`);
          process.exit(1);
        }

        const stratIdx = args.indexOf("--strategy");
        const strategyOverride =
          stratIdx !== -1 ? (args[stratIdx + 1] as ScalingStrategy) : undefined;

        const updated = setAppScale(appId, scale, strategyOverride);
        if (isJson) {
          console.log(
            JSON.stringify(
              {
                success: true,
                message: `Saved launcher scale ${scale}x for ${updated.name}`,
                app: updated,
              },
              null,
              2,
            ),
          );
        } else {
          console.log(`✓ Saved launcher scale ${scale}x for ${updated.name} (${updated.id})`);
          console.log(`  Updated: ${updated.desktopPath}`);
          console.log(`  Exec:    ${updated.exec}`);
          console.log(
            "  Fully quit the application, including its tray icon, then relaunch through the desktop launcher.",
          );
          console.log("  Direct app shortcuts may bypass the saved launcher override.");
        }
        break;
      }

      case "reset": {
        const appId = args[1];
        if (!appId) {
          console.error("Usage: omarchy-app-dpi reset <app-id> [--json]");
          process.exit(1);
        }

        const result = resetAppScale(appId);
        if (isJson) {
          console.log(JSON.stringify(result, null, 2));
        } else {
          console.log(`✓ ${result.message}`);
          console.log("  Restart the application to apply default scaling.");
        }
        break;
      }

      default: {
        console.error(`Unknown command: ${command}`);
        printHelp();
        process.exit(1);
      }
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    if (isJson) {
      console.error(JSON.stringify({ success: false, error: message }));
    } else {
      console.error(`Error: ${message}`);
    }
    process.exit(1);
  }
}
