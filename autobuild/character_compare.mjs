#!/usr/bin/env node
// P2-1b: the current family and the candidate bodies from the other character
// packs, stood in ONE row in the same light, so they compare in the same frame.
// Candidates are static previews made by `tools/convert_character.gd` (posed in
// their own idle, painted like the figures, eyes and hair dropped) under
// res://art/characters/candidates/ (gitignored).
//
//   node autobuild/character_compare.mjs [--figures=dad,mom,res://...] [--out=autobuild/frames/p2_1b] [--import]
//
// Three shots per run: front (6 m), three-quarter (6 m), and far (20 m).
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, renameSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const GODOT = process.env.GODOT_BIN || "godot";
const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const C = "res://art/characters/candidates/";
const OUT = resolve(ROOT, arg("out", "autobuild/frames/p2_1b"));
const NAME = arg("name", "compare");
const FIGURES = arg("figures", ["dad", "mom", `${C}lp_male.glb`, `${C}lp_female.glb`, `${C}lp_male_smooth.glb`,
  `${C}um_male.glb`, `${C}um_female.glb`].join(",")).split(",");
const ANSI = /\x1b\[[0-9;]*m/g;

if (process.argv.includes("--import")) {
  const r = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"],
    { cwd: ROOT, encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26 });
  console.log(`import exit ${r.status}`);
}

// House A's back yard toward its plain back wall, the turnaround's spot (P2-5).
const X = 1700, Y = 300, Z = 3000, SPACING = 85;
const xs = FIGURES.map((_, i) => X + (i - (FIGURES.length - 1) / 2) * SPACING);
const shots = [
  { cam: [X, Y + 100, Z + 400], look: [X, Y + 95, Z] }, // front, 4 m
  { cam: [X + 330, Y + 120, Z + 330], look: [X, Y + 95, Z] }, // three-quarter
  { cam: [X, Y + 400, Z + 2000], look: [X, Y + 90, Z] }, // far, 20 m, chase-ish height
];
// --close: the heads and hands of the middle of the row, 1.8 m away.
if (process.argv.includes("--close")) shots.push({ cam: [X, Y + 150, Z + 180], look: [X, Y + 130, Z] });
mkdirSync(OUT, { recursive: true });
const stem = join(OUT, `${NAME}.png`);
const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
  "--capture", "--capture-clean", "--capture-delay=3", `--capture-path=${stem}`];
for (const s of shots) a.push(`--capture-at=${s.cam.join(",")}`, `--capture-look=${s.look.join(",")}`);
// Everyone faces +z (toward the front camera): yaw 0.
// An entry may carry a clip of the animation set after a "+": dad+jog@0.2.
FIGURES.forEach((f, i) => a.push(`--capture-figure=${xs[i]},${Y},${Z},0,${f.replace("+", ",")}`));
const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
const views = ["front", "three_quarter", "far", "close"].slice(0, shots.length);
views.forEach((v, i) => {
  const numbered = stem.replace(/\.png$/, `_${i + 1}.png`);
  const named = stem.replace(/\.png$/, `_${v}.png`);
  if (existsSync(numbered)) renameSync(numbered, named);
  console.log(`${named}: ${existsSync(named) ? "ok" : "MISSING"}`);
});
console.log(`left to right: ${FIGURES.join(" | ")}`);
const errors = out.split("\n").filter((l) => /ERROR/.test(l) && !/leaked|RID allocations|PagedAllocator/.test(l));
if (errors.length) console.log(errors.slice(0, 12).join("\n"));
