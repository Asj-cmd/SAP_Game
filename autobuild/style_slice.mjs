#!/usr/bin/env node
// P1-5 style slice: the same room (House A's study, a cash/vault room) under each
// theme variant, from the same four views, with a dad and a mom figure stood in it.
//
//   node autobuild/style_slice.mjs [--variants=a,b,c] [--import]
//
// Variants are whole ArtTheme files (godot/art/theme/slice_<v>.tres), swapped in
// with `--art-theme=` - no code differs between them. Frames land in
// autobuild/slice/<variant>_<view>.png. Windowed (the real GPU); a run is ~1 min
// a variant. `--import` first lets Godot import new art (figure_bake.mjs output).
import { spawnSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readdirSync, renameSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const GODOT = process.env.GODOT_BIN || "godot";
const OUT = join(HERE, "slice");
const ANSI = /\x1b\[[0-9;]*m/g;
const argv = process.argv.slice(2);
const opt = (name, fallback) => (argv.find((a) => a.startsWith(`--${name}=`)) ?? `--${name}=${fallback}`).split("=")[1];
const variants = opt("variants", "a,b,c").split(",");

// Study A: x/z 380-1380, floor y 660; cash at (630, 880) and (1030, 880).
const FLOOR = 660;
const FIGURES = [
  `780,${FLOOR},720,40,res://art/characters/figure_male.gltf`,
  `1010,${FLOOR},700,20,res://art/characters/figure_female.gltf`,
];
// Four views, in shot order: what a player sees, the room, the figures, against the light.
const VIEWS = [
  { name: "chase", chase: [1250, FLOOR, 1200], facing: [630, FLOOR, 880], pitch: -14 },
  { name: "room", at: [1340, 960, 1340], look: [760, 700, 720] },
  { name: "figures", at: [905, 815, 1010], look: [895, 790, 700] },
  { name: "backlit", at: [440, 880, 440], look: [960, 740, 820] },
];

if (argv.includes("--import")) {
  const r = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"],
    { cwd: ROOT, encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26 });
  console.log(`import exit ${r.status}`);
  const errors = `${r.stdout}\n${r.stderr}`.replace(ANSI, "").split("\n").filter((l) => /ERROR|error/.test(l));
  if (errors.length) console.log(errors.slice(0, 20).join("\n"));
}

mkdirSync(OUT, { recursive: true });
for (const v of variants) {
  const shot = join(OUT, `${v}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
    `--art-theme=res://art/theme/slice_${v}.tres`, "--capture", "--capture-clean", "--capture-stats",
    "--capture-delay=3", `--capture-path=${shot}`, ...FIGURES.map((f) => `--capture-figure=${f}`)];
  for (const view of VIEWS.filter((x) => x.at)) a.push(`--capture-at=${view.at.join(",")}`, `--capture-look=${view.look.join(",")}`);
  for (const view of VIEWS.filter((x) => x.chase)) {
    a.push(`--capture-chase=${view.chase.join(",")}`, `--capture-facing=${view.facing.join(",")}`, `--capture-pitch=${view.pitch}`);
  }
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  // Shots are numbered: --capture-at ones first, then chase ones (FrameCapture).
  const order = [...VIEWS.filter((x) => x.at), ...VIEWS.filter((x) => x.chase)];
  order.forEach((view, i) => {
    const from = join(OUT, `${v}_${i + 1}.png`);
    if (existsSync(from)) renameSync(from, join(OUT, `${v}_${view.name}.png`));
  });
  const stats = [...out.matchAll(/^RENDER_STATS (\S+) (\{.*\})\s*$/gm)].map((m) => [m[1], JSON.parse(m[2])]);
  console.log(`variant ${v}: exit ${r.status}, ${stats.length} shots`);
  stats.forEach(([name, s], i) => console.log(`  ${order[i]?.name ?? name}: draws ${s.draw_calls}, tris ${s.triangles}`));
  const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR|push_error/.test(l));
  if (errors.length) console.log(errors.slice(0, 12).join("\n"));
}
console.log(`frames: ${readdirSync(OUT).filter((f) => f.endsWith(".png")).length} in ${OUT}`);
