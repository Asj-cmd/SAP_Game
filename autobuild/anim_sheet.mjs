#!/usr/bin/env node
// Contact sheets for the figure animation set (P2-2, P2-3): for each clip, a
// row of figures each held at a different moment of it, stood in the strip
// between the houses, shot side-on and from three-quarters front.
//
//   node autobuild/anim_sheet.mjs [--clips=walk,jog,...] [--member=dad] [--count=6]
//        [--out=autobuild/frames/p2_2] [--import]
//
// Writes <out>/<clip>[_<member>]_{side,front}.png. Moments are spread evenly over a
// loop (start included, end left out: it is the start again) and from first to
// last frame of a one-shot. Clip lengths come from
// godot/art/characters/figure_anims.json (written by tools/build_figure_anims.gd).
// Drawn-only figures (--capture-figure ...,clip@t); the sim is untouched.
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const GODOT = process.env.GODOT_BIN || "godot";
const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const SET = JSON.parse(readFileSync(join(ROOT, "godot/art/characters/figure_anims.json"), "utf8"));
const CLIPS = arg("clips", Object.keys(SET).join(",")).split(",");
const MEMBER = arg("member", "");
const COUNT = Number(arg("count", "6"));
const OUT = resolve(ROOT, arg("out", "autobuild/frames/p2_2"));
const ANSI = /\x1b\[[0-9;]*m/g;

if (process.argv.includes("--import")) {
  const r = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"],
    { cwd: ROOT, encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26 });
  console.log(`import exit ${r.status}`);
}

// The strip between House A (x <= 2440) and House B (x >= 2960), ground top y 300.
const Y = 300;
const Z = 1000;
const SPACING = 90; // six fit inside the 520-wide strip
// The cameras look toward +z, so screen right is -x: the row runs from +x (first
// moment, screen left) to -x, and the figures face -x (yaw -90), i.e. screen right.
const xs = Array.from({ length: COUNT }, (_, i) => 2700 - (i - (COUNT - 1) / 2) * SPACING);
const SHOTS = [
  { name: "side", at: [2700, 390, Z - 540], look: [2700, 385, Z] },
  // Kept inside the strip (House A's wall is at x 2440).
  { name: "front", at: [2700 - 190, 420, Z - 500], look: [2700, 385, Z] },
];

mkdirSync(OUT, { recursive: true });
for (const clip of CLIPS) {
  const info = SET[clip];
  if (!info) { console.log(`${clip}: not in the set`); continue; }
  const times = xs.map((_, i) => {
    if (info.length <= 0.05) return 0;
    return info.loop ? (i * info.length) / COUNT : (i * info.length) / Math.max(1, COUNT - 1);
  });
  const stem = join(OUT, `${clip}${MEMBER ? `_${MEMBER}` : ""}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
    "--capture", "--capture-clean", "--capture-delay=2", `--capture-path=${stem}`];
  // Facing -x, so the side shot sees them in profile walking left to right.
  xs.forEach((x, i) => a.push(`--capture-figure=${x},${Y},${Z},-90,${MEMBER},${clip}@${times[i].toFixed(3)}`));
  for (const s of SHOTS) a.push(`--capture-at=${s.at.join(",")}`, `--capture-look=${s.look.join(",")}`);
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  const made = SHOTS.map((s, i) => {
    const from = stem.replace(/\.png$/, `_${i + 1}.png`);
    const to = stem.replace(/\.png$/, `_${s.name}.png`);
    if (existsSync(from)) renameSync(from, to);
    return existsSync(to) ? s.name : `${s.name} MISSING`;
  });
  console.log(`${clip}: ${made.join(", ")}  t=${times.map((t) => t.toFixed(2)).join(" ")}`);
  const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR/.test(l) && !/leaked|RID allocations|PagedAllocator/.test(l));
  if (errors.length) console.log(errors.slice(0, 8).join("\n"));
}
