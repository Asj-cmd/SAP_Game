#!/usr/bin/env node
// The family lineup (P2-1, reused by P2-5): every member of the theme's family
// stood in a row in the strip between the two houses, shot from the front, the
// side and the back up close, and from the front at 20 m and 40 m (STYLE §2.2:
// the four sizes must read by outline alone at 20 m).
//
//   node autobuild/family_lineup.mjs [--out=autobuild/frames/p2_1] [--import]
//        [--theme=res://art/theme/default_theme.tres] [--members=dad,mom,...]
//
// Writes <out>/lineup_{front,front_20m,front_40m,side,back}.png and prints the
// render counters per shot. Drawn-only figures (--capture-figure); the sim and
// the level are untouched.
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
const OUT = resolve(ROOT, arg("out", "autobuild/frames/p2_1"));
const THEME = arg("theme", "res://art/theme/default_theme.tres");
const MEMBERS = arg("members", "dad,mom,elder_girl,elder_boy,younger_girl,younger_boy").split(",");
const ANSI = /\x1b\[[0-9;]*m/g;

if (process.argv.includes("--import")) {
  const r = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"],
    { cwd: ROOT, encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26 });
  console.log(`import exit ${r.status}`);
}

// The strip between House A (x <= 2440) and House B (x >= 2960), ground top y 300.
const Y = 300;
const Z = 1000;
const SPACING = 85;
const xs = MEMBERS.map((_, i) => 2700 + (i - (MEMBERS.length - 1) / 2) * SPACING);
const CLOSE = { at: [2700, 400, 560], look: [2700, 390, Z] };
const RUNS = [
  { yaw: 180, shots: [
    { name: "front", ...CLOSE },
    { name: "front_20m", at: [2700, 470, Z - 2000], look: [2700, 390, Z] },
    { name: "front_40m", at: [2700, 600, Z - 4000], look: [2700, 390, Z] },
  ] },
  { yaw: 90, shots: [{ name: "side", ...CLOSE }] },
  { yaw: 0, shots: [{ name: "back", ...CLOSE }] },
];

mkdirSync(OUT, { recursive: true });
for (const run of RUNS) {
  const stem = join(OUT, `lineup_yaw${run.yaw}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
    `--art-theme=${THEME}`, "--capture", "--capture-clean", "--capture-stats", "--capture-delay=3",
    `--capture-path=${stem}`];
  MEMBERS.forEach((m, i) => a.push(`--capture-figure=${xs[i]},${Y},${Z},${run.yaw},${m}`));
  for (const s of run.shots) a.push(`--capture-at=${s.at.join(",")}`, `--capture-look=${s.look.join(",")}`);
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  const stats = [...out.matchAll(/^RENDER_STATS (\S+) (\{.*\})\s*$/gm)].map((m) => JSON.parse(m[2]));
  run.shots.forEach((s, i) => {
    const from = run.shots.length > 1 ? join(OUT, `lineup_yaw${run.yaw}_${i + 1}.png`) : stem;
    const to = join(OUT, `lineup_${s.name}.png`);
    if (existsSync(from)) renameSync(from, to);
    const st = stats[i];
    console.log(`${s.name}: ${existsSync(to) ? "ok" : "MISSING"}${st ? `, draws ${st.draw_calls}, tris ${st.triangles}` : ""}`);
  });
  const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR|figure height/.test(l));
  if (errors.length) console.log(errors.slice(0, 12).join("\n"));
}
