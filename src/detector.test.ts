import { describe, expect, test } from "bun:test";
import { detectToolkit } from "./detector.ts";

const steamClient = { toolkit: "steam", strategy: "GDK_SCALE" } as const;
const game = { toolkit: "game", strategy: "IN_GAME_SETTINGS" } as const;
const unknown = { toolkit: "unrecognized", strategy: "UNIVERSAL_FALLBACK" } as const;

describe("Steam launch context", () => {
  test.each([
    "steam",
    "/usr/bin/steam %U",
    "steam -silent",
    "steam -bigpicture",
    "steam steam://open/games",
    "steam steam://open/bigpicture",
    "env GDK_SCALE=1 /usr/bin/steam %U",
    '/usr/bin/env HOME="/home/steam user" GDK_SCALE=1 /usr/bin/steam -silent',
    "STEAM_RUNTIME=1 /usr/bin/steam -bigpicture",
    '"/opt/Steam Client/steam" %U',
  ])("classifies client %s despite Game category", (execLine) => {
    expect(detectToolkit(null, { execLine, categories: "Network;Game;" })).toEqual(steamClient);
  });

  test.each([
    "steam steam://rungameid/1808500",
    "/usr/bin/steam steam://run/1808500",
    "env GDK_SCALE=1 /usr/bin/steam steam://rungameid/1808500",
    "steam -applaunch 1808500",
    "/usr/bin/steam -silent -applaunch 1808500 -windowed",
    'steam "steam://run/1808500//-windowed/"',
  ])("classifies explicit game %s without a Game category", (execLine) => {
    const context = { execLine, categories: "" };
    expect(detectToolkit(null, context)).toEqual(game);
  });

  test("keeps the same launcher context-specific across client and game calls", () => {
    expect(detectToolkit(null, { execLine: "steam steam://rungameid/1808500" })).toEqual(game);
    expect(detectToolkit(null, { execLine: "steam", categories: "Game;" })).toEqual(steamClient);
    expect(detectToolkit(null, { execLine: "steam -applaunch 1808500" })).toEqual(game);
  });

  test.each([
    "steam-helper steam://open/games",
    "/usr/bin/notsteam steam://rungameid/1808500",
    "browser https://example.org/steam",
    "browser steam://run/1808500",
    "browser steam steam://rungameid/1808500",
    "env APP=steam browser https://example.org/steam",
  ])("does not mistake %s for the Steam launcher", (execLine) => {
    expect(detectToolkit(null, { execLine })).toEqual(unknown);
  });

  test.each([
    "steam https://example.org/steam://rungameid/1808500",
    "steam steam://open/games/steam://run/1808500",
    "steam --name=-applaunch",
    "steam -applaunch not-a-game-id",
  ])("does not mistake client argument %s for a game launch", (execLine) => {
    expect(detectToolkit(null, { execLine, categories: "Game;" })).toEqual(steamClient);
  });

  test("retains the Game category fallback for unrelated applications", () => {
    expect(detectToolkit(null, { execLine: "arc-raiders", categories: "Game;Action;" })).toEqual(
      game,
    );
  });
});
