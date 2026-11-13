#!/usr/bin/env node
// What the renderer does for each view in views.json: draw calls, triangles, objects,
// and frame time on THIS machine's GPU, checked against the budgets in render_budget.json.
//
//   node autobuild/render_stats.mjs                    every view, 120 timed frames each
//   node autobuild/render_stats.mjs --views=room_      only views whose name starts so
//   node autobuild/render_stats.mjs --timing=0         counters only (fast, no frame time)
//
// Runs the game windowed (`--capture --capture-clean --capture-timing=N`): the counters are
// zero under --headless, and frame time is only meaningful on the real GPU (STYLE.md §Budgets).
// Each run also writes the frame to autobuild/frames/stats/<view>.png, so a number can be
// matched to a picture. Results: autobuild/frames/render_stats.json. Not a verify gate (yet):
// exit code is 0 unless a view failed to report; views over budget are listed.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const GODOT_PROJECT = join(ROOT, "godot");
const GODOT = process.env.GODOT_BIN || "godot";
const OUT_DIR = join(HERE, "frames", "stats");
const ANSI = /\x1b\[[0-9;]*m/g;

const argv = process.argv.slice(2);
const opt = (name, fallback) => (argv.find((a) => a.startsWith(`--${name}=`)) ?? `--${name}=${fallback}`).split("=")[1];
const prefix = opt("views", "");
const timing = Number(opt("timing", "120"));

const views = JSON.parse(readFileSync(join(HERE, "views.json"), "utf8")).views.filter((v) => v.name.startsWith(prefix));
const budgetPath = join(HERE, "render_budget.json");
const budget = existsSync(budgetPath) ? JSON.parse(readFileSync(budgetPath, "utf8")).per_view ?? {} : {};
mkdirSync(OUT_DIR, { recursive: true });

const rows = [];
const missing = [];
let adapter = "";
for (const v of views) {
  const path = join(OUT_DIR, `${v.name}.png`);
  const a = ["--rendering-driver", "opengl3", "--path", GODOT_PROJECT, "--", "--capture", "--capture-clean",
    `--capture-delay=${v.delay ?? 3}`, `--capture-path=${path}`, timing > 0 ? `--capture-timing=${timing}` : "--capture-stats"];
  if (v.chase) {
    a.push(`--capture-chase=${v.chase.join(",")}`);
    if (v.facing) a.push(`--capture-facing=${v.facing.join(",")}`);
    if (v.pitch != null) a.push(`--capture-pitch=${v.pitch}`);
  } else {
    a.push(`--capture-at=${v.at.join(",")}`);
    if (v.look) a.push(`--capture-look=${v.look.join(",")}`);
  }
  const r = spawnSync(GODOT, a, { cwd: ROOT, encoding: "utf8", timeout: 180000, maxBuffer: 1 << 26 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  const m = out.match(/^RENDER_STATS \S+ (\{.*\})\s*$/m);
  if (!m) { missing.push(v.name); console.log(`  FAIL  ${v.name}: no RENDER_STATS line`); continue; }
  const s = JSON.parse(m[1]);
  adapter = s.adapter;
  const over = Object.entries(budget).filter(([k, max]) => s[k] != null && s[k] > max).map(([k]) => k);
  rows.push({ view: v.name, ...s, over });
  console.log(`  ${v.name.padEnd(28)} draws ${String(s.draw_calls).padStart(5)}  tris ${String(s.triangles).padStart(7)}  objs ${String(s.objects).padStart(5)}` +
    (timing > 0 ? `  frame ${s.frame_ms_median.toFixed(1).padStart(5)} / p95 ${s.frame_ms_p95.toFixed(1).padStart(5)} ms  gpu ${s.seat_gpu_ms_median.toFixed(1).padStart(5)} ms` : "") +
    (over.length ? `  OVER: ${over.join(", ")}` : ""));
}

const col = (k) => rows.map((r) => r[k]).filter((x) => typeof x === "number").sort((x, y) => x - y);
const med = (xs) => (xs.length ? xs[Math.floor((xs.length - 1) / 2)] : 0);
const keys = ["draw_calls", "triangles", "objects", ...(timing > 0 ? ["frame_ms_median", "frame_ms_p95", "seat_gpu_ms_median"] : [])];
const summary = Object.fromEntries(keys.map((k) => [k, { median: med(col(k)), max: col(k).at(-1) ?? 0, worst_view: rows.find((r) => r[k] === col(k).at(-1))?.view }]));
console.log(`\n${rows.length} views on ${adapter || "?"}${timing > 0 ? `, ${timing} timed frames each` : ""}`);
for (const [k, s] of Object.entries(summary)) console.log(`  ${k.padEnd(20)} median ${s.median}  max ${s.max} (${s.worst_view})`);
const overViews = rows.filter((r) => r.over.length);
console.log(overViews.length ? `\nOver budget: ${overViews.map((r) => `${r.view} (${r.over.join(", ")})`).join("; ")}` : "\nAll views within render_budget.json.");
writeFileSync(join(HERE, "frames", "render_stats.json"), JSON.stringify({ adapter, timing, summary, rows }, null, 2) + "\n");
process.exit(missing.length ? 1 : 0);
