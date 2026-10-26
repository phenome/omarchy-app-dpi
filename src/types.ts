export type ToolkitType =
  | "slint"
  | "qt6"
  | "qt5"
  | "gtk4"
  | "gtk3"
  | "electron"
  | "webapp"
  | "game"
  | "gecko"
  | "java"
  | "unrecognized"
  | "unknown";

export type ScalingStrategy =
  | "SLINT_SCALE_FACTOR"
  | "QT_SCALE_FACTOR"
  | "GDK_DPI_SCALE"
  | "CHROME_SCALE_FLAG"
  | "JAVA_UI_SCALE"
  | "BROWSER_ZOOM"
  | "IN_GAME_SETTINGS"
  | "UNIVERSAL_FALLBACK"
  | "UNKNOWN";

export interface AppInfo {
  id: string; // e.g. "com.flectar.mail"
  name: string; // e.g. "Flectar Mail"
  icon: string; // e.g. "com.flectar.mail" or "/path/to/icon.png"
  exec: string;
  resolvedBinary: string | null;
  toolkit: ToolkitType;
  strategy: ScalingStrategy;
  currentScale: number;
  isOverridden: boolean;
  desktopPath: string;
  systemDesktopPath: string | null;
  comment?: string;
  terminal?: boolean;
  noDisplay?: boolean;
}
