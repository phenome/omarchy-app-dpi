# omarchy-app-dpi

Per-application DPI and scaling manager for [Omarchy](https://omarchy.org/) Linux.

Allows overriding the UI scaling factor of individual applications without altering global monitor scaling. Automatically inspects ELF binaries and wrapper scripts to detect application toolkits deterministically and injects the optimal scaling environment variable or command-line flag into user desktop entries (`~/.local/share/applications/*.desktop`).

---

## Supported Toolkits & Strategies

| Toolkit | Detection Criteria | Scaling Strategy |
| :--- | :--- | :--- |
| **Slint** (Rust) | ELF symbols `SLINT_SCALE_FACTOR`, `slint_core`, `slint::` | `env SLINT_SCALE_FACTOR=<scale>` |
| **Qt 6** | Dynamic dependency `libQt6Core.so` | `env QT_SCALE_FACTOR=<scale>` |
| **Qt 5** | Dynamic dependency `libQt5Core.so` | `env QT_SCALE_FACTOR=<scale>` |
| **GTK 4** | Dynamic dependency `libgtk-4.so` | `env GDK_SCALE=1 GDK_DPI_SCALE=<scale>` |
| **GTK 3** | Dynamic dependency `libgtk-3.so` | `env GDK_SCALE=1 GDK_DPI_SCALE=<scale>` |
| **Electron / Chromium** | ASAR archive, `force-device-scale-factor` flag | `--force-device-scale-factor=<scale>` |
| **Java** (AWT/Swing/JavaFX) | Executable `java` or `libjvm.so` | `-Dsun.java2d.uiScale=<scale>` |
| **Unknown** | Fallback | Generic environment variable wrapper |

---

## Installation

### Via Omarchy Plugin Manager

```bash
omarchy plugin add https://github.com/phenome/omarchy-app-dpi.git --enable
```

### CLI Tool Setup

To make the `omarchy-app-dpi` command available in your terminal:

```bash
ln -sf ~/.config/omarchy/plugins/phenome.app-dpi/bin/omarchy-app-dpi ~/.local/bin/omarchy-app-dpi
```

---

## CLI Usage

### List Installed Applications

```bash
# Formatted list
omarchy-app-dpi list

# Filtered search
omarchy-app-dpi list --search chrome

# JSON output
omarchy-app-dpi list --json
```

### Inspect an Application

```bash
omarchy-app-dpi inspect com.flectar.mail
omarchy-app-dpi inspect google-chrome
```

### Set Scaling Factor

```bash
# Scale Flectar Mail to 85%
omarchy-app-dpi set com.flectar.mail 0.85

# Scale Chrome to 125%
omarchy-app-dpi set google-chrome 1.25
```

### Reset to Default Scaling

```bash
omarchy-app-dpi reset com.flectar.mail
```

---

## Keyboard Shortcut

To open the graphical scaling manager with `SUPER + CTRL + D`, add the following to `~/.config/hypr/bindings.lua`:

```lua
o.rebind("SUPER + CTRL + D", "App Scaling", { panel = "phenome.app-dpi" })
```

Then reload Hyprland bindings:

```bash
hyprctl reload
```

---

## Development & Linting

This repository uses [Biome](https://biomejs.dev/) for code linting and formatting, [Lefthook](https://github.com/evilmartians/lefthook) for Git pre-commit hooks, and Bun's native typechecker:

```bash
# Typecheck
bun check

# Lint & check formatting
bun run lint

# Format code
bun run format
```

---

## License

MIT © [phenome](https://github.com/phenome)
