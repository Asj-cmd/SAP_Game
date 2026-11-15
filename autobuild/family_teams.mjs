#!/usr/bin/env node
// Both families side by side in their outfits (P2-1b, D3): family A's members
// on screen left, family B's on screen right, in House A's back yard (the
// turnaround spot: plain back wall behind, sun on their fronts), shot from
// 9 m, 20 m and 40 m. Each member and each team must be told apart in the frame.
//
//   node autobuild/family_teams.mjs [--out=autobuild/frames/p2_1b] [--tell=none]
//        [--members=dad,mom,elder_girl,younger_boy] [--theme=res://...] [--clip=jog@0.2]
//
// Writes <out>/teams_{9m,20m,40m}.png. Drawn-only figures; the sim is untouched.
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
const OUT = resolve(ROOT, arg("out", "autobuild/frames/p2_1b"));
const THEME = arg("theme", "res://art/theme/default_theme.tres");
const TELL = arg("tell", "none");
const CLIP = arg("clip", "");
const MEMBERS = arg("members", "dad,mom,elder_girl,elder_boy,younger_girl,younger_boy").split(",");
const STEM = arg("name", "teams");

const X = 1400, Y = 300, Z = 3000, SPACING = 95, GAP = 160;
// The camera looks toward -z, so screen right is +x.
const row = [];
MEMBERS.forEach((m, i) => row.push({ who: `team_a/${m}`, x: X - GAP / 2 - (MEMBERS.length - 1 - i) * SPACING }));
MEMBERS.forEach((m, i) => row.push({ who: `team_b/${m}`, x: X + GAP / 2 + i * SPACING }));
const SHOTS = [["9m", 900, 110], ["20m", 2000, 170], ["40m", 4000, 300]];

mkdirSync(OUT, { recursive: true });
const stem = join(OUT, `${STEM}.png`);
const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
  `--art-theme=${THEME}`, `--team-tell=${TELL}`, "--capture", "--capture-clean", "--capture-delay=3",
  `--capture-path=${stem}`];
for (const f of row) a.push(`--capture-figure=${f.x},${Y},${Z},0,${f.who}${CLIP ? `,${CLIP}` : ""}`);
for (const [, d, up] of SHOTS) a.push(`--capture-at=${X},${Y + up},${Z + d}`, `--capture-look=${X},${Y + 90},${Z}`);
const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`;
SHOTS.forEach(([name], i) => {
  const from = join(OUT, `${STEM}_${i + 1}.png`);
  const to = join(OUT, `${STEM}_${name}.png`);
  if (existsSync(from)) renameSync(from, to);
  console.log(`${name}: ${existsSync(to) ? to : "MISSING"}`);
});
const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR|figure height/.test(l));
if (errors.length) console.log(errors.slice(0, 12).join("\n"));
