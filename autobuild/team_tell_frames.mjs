#!/usr/bin/env node
// The D3 team tell (P2-4): both families stood in one row in the strip between
// the houses, paired by roster slot (A dad, B dad, A mom, B mom, A elder, B
// elder, A younger, B younger), shot close (about 4.4 m), at 20 m and at 40 m,
// once per team-tell setting. The HUD overlays (marker, minimap) are kept in the
// shot (--capture-hud); this machine's seat is team_a, so the marker goes over
// the four team_a figures and the minimap shows team_a only.
//
//   node autobuild/team_tell_frames.mjs [--out=autobuild/frames/p2_4]
//        [--sets=none,marker,minimap,wristband,kid_swap,default,all]
//
// Writes <out>/<set>_{close,20m,40m}.png. Drawn-only figures (--capture-figure
// with team:slot); the sim and the level are untouched.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, renameSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const OUT = resolve(ROOT, arg("out", "autobuild/frames/p2_4"));
const SETS = {
  none: "none",
  marker: "marker",
  minimap: "minimap",
  wristband: "wristband",
  kid_swap: "kid_swap",
  default: null, // art/theme/team_tell.tres (no --team-tell)
  all: "marker,minimap,wristband,kid_swap",
};
const wanted = arg("sets", Object.keys(SETS).join(",")).split(",");
const ANSI = /\x1b\[[0-9;]*m/g;

// The strip between House A (x <= 2440) and House B (x >= 2960), ground top y 300.
const Y = 300;
const Z = 1000;
const SPACING = 60;
const ORDER = ["team_a:0", "team_b:0", "team_a:1", "team_b:1", "team_a:2", "team_b:2", "team_a:3", "team_b:3"];
const xs = ORDER.map((_, i) => 2700 + (i - (ORDER.length - 1) / 2) * SPACING);
const SHOTS = [
  { name: "close", at: [2700, 400, 560], look: [2700, 390, Z] },
  { name: "20m", at: [2700, 470, Z - 2000], look: [2700, 390, Z] },
  { name: "40m", at: [2700, 600, Z - 4000], look: [2700, 390, Z] },
];

mkdirSync(OUT, { recursive: true });
for (const set of wanted) {
  if (!(set in SETS)) {
    console.log(`unknown set ${set}`);
    continue;
  }
  const stem = join(OUT, `${set}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
    "--capture", "--capture-clean", "--capture-hud", "--capture-delay=3", `--capture-path=${stem}`];
  if (SETS[set] !== null) a.push(`--team-tell=${SETS[set]}`);
  ORDER.forEach((who, i) => a.push(`--capture-figure=${xs[i]},${Y},${Z},180,${who}`));
  for (const s of SHOTS) a.push(`--capture-at=${s.at.join(",")}`, `--capture-look=${s.look.join(",")}`);
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  const done = SHOTS.map((s, i) => {
    const from = join(OUT, `${set}_${i + 1}.png`);
    const to = join(OUT, `${set}_${s.name}.png`);
    if (existsSync(from)) renameSync(from, to);
    return `${s.name} ${existsSync(to) ? "ok" : "MISSING"}`;
  });
  console.log(`${set}: ${done.join(", ")}`);
  const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR/.test(l));
  if (errors.length) console.log(errors.slice(0, 12).join("\n"));
}
