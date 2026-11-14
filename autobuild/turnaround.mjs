#!/usr/bin/env node
// Turnaround sheets (P2-5): one capture per family member, the same member
// stood four times in a row and turned a quarter more each time, so one frame
// shows it from the front, its right side, the back and its left side.
//
//   node autobuild/turnaround.mjs [--members=dad,mom,...] [--out=autobuild/slice]
//        [--theme=res://art/theme/default_theme.tres] [--clip=] [--import]
//
// Writes <out>/turnaround_<member>.png and prints the render counters per shot.
// Every sheet uses the same camera and spacing, so heights compare across sheets.
// Each copy is turned against its own line of sight to the camera (not against
// the world axis), so the copies off the middle are seen at exactly 0/90/180/270
// rather than skewed by perspective. Drawn-only figures (--capture-figure); the
// sim and the level are untouched.
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
const OUT = resolve(ROOT, arg("out", "autobuild/slice"));
const THEME = arg("theme", "res://art/theme/default_theme.tres");
const CLIP = arg("clip", "");
const MEMBERS = arg("members", "dad,mom,elder_girl,elder_boy,younger_girl,younger_boy").split(",");
const ANSI = /\x1b\[[0-9;]*m/g;

if (process.argv.includes("--import")) {
  const r = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"],
    { cwd: ROOT, encoding: "utf8", timeout: 600000, maxBuffer: 1 << 26 });
  console.log(`import exit ${r.status}`);
}

// House A's back yard (House A spans x 350-2440, z 350-2440; ground top y 300),
// shot toward the house, so its plain back wall is the backdrop and the sun,
// which comes from +z, lights the figures from the camera's side. The strip
// between the houses put half the row in House A's shadow.
const X = 1700; // clear of the back door (behind x ~1250-1400)
const Y = 300;
const Z = 3000;
const SPACING = 105;
const CAM = [X, Y + 95, Z + 300];
const LOOK = [X, Y + 88, Z];
// The camera looks toward -z, so screen right is +x: the row runs from -x
// (screen left, the front view) to +x.
const xs = [0, 1, 2, 3].map((i) => X + (i - 1.5) * SPACING);
const deg = (r) => (r * 180) / Math.PI;
// Yaw 0 faces +z and yaw 90 faces +x, so the yaw that faces a point is
// atan2(dx, dz). +90 from facing the camera turns the figure to face screen
// right, its RIGHT side to the camera (checked by the wristband, which is on
// the left wrist); +180 is its back; +270 its left side.
const VIEWS = ["front", "right", "back", "left"];
const yaws = xs.map((x, i) => deg(Math.atan2(CAM[0] - x, CAM[2] - Z)) + i * 90);

mkdirSync(OUT, { recursive: true });
for (const member of MEMBERS) {
  const stem = join(OUT, `turnaround_${member}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", join(ROOT, "godot"), "--",
    `--art-theme=${THEME}`, "--capture", "--capture-clean", "--capture-stats", "--capture-delay=3",
    `--capture-path=${stem}`, `--capture-at=${CAM.join(",")}`, `--capture-look=${LOOK.join(",")}`];
  xs.forEach((x, i) => a.push(
    `--capture-figure=${x},${Y},${Z},${yaws[i].toFixed(2)},${member}${CLIP ? `,${CLIP}` : ""}`));
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 240000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  // A single --capture-at may be written as <stem>.png or <stem>_1.png.
  const numbered = stem.replace(/\.png$/, "_1.png");
  if (existsSync(numbered)) renameSync(numbered, stem);
  const st = [...out.matchAll(/^RENDER_STATS (\S+) (\{.*\})\s*$/gm)].map((m) => JSON.parse(m[2]))[0];
  console.log(`${member}: ${existsSync(stem) ? "ok" : "MISSING"} (${VIEWS.join(", ")}, yaw ${
    yaws.map((y) => y.toFixed(1)).join(" ")})${st ? `, draws ${st.draw_calls}, tris ${st.triangles}` : ""}`);
  const errors = out.split("\n").filter((l) => /ERROR|SCRIPT ERROR|figure height/.test(l)
    && !/leaked|RID allocations|PagedAllocator/.test(l));
  if (errors.length) console.log(errors.slice(0, 12).join("\n"));
}
