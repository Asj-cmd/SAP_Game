#!/usr/bin/env node
// One command that answers "is the project still healthy?" for the autonomous loop.
//
//   node autobuild/verify.mjs              tests + bot match (the default gate)
//   node autobuild/verify.mjs --frames     also capture the views in views.json
//   node autobuild/verify.mjs --quick      tests only
//   node autobuild/verify.mjs --update-baseline   raise the pinned test counts / metrics budget
//
// Needs the Godot 4.7 binary: set GODOT_BIN (e.g. C:\Godot\Godot_v4.7-stable_win64_console.exe).
// Exit code 0 = healthy, 1 = something regressed. Output is written for a model to read.
//
// Pinned counts exist because a smaller green number is not a passing one: a suite that
// silently stops running half its cases still reports "0 failed".

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const GODOT_PROJECT = join(ROOT, "godot");
const GODOT = process.env.GODOT_BIN || "godot";
const BASELINE_PATH = join(HERE, "test_baseline.json");
const BUDGET_PATH = join(HERE, "metrics_budget.json");
const VIEWS_PATH = join(HERE, "views.json");
const FRAMES_DIR = join(HERE, "frames");
const ANSI = /\x1b\[[0-9;]*m/g;

const args = new Set(process.argv.slice(2));
const failures = [];

function godot(godotArgs, { timeoutSec = 300, wrap = false } = {}) {
  let cmd = GODOT;
  let argv = godotArgs;
  // Frame capture needs a display. On a headless Linux box, borrow a virtual one.
  if (wrap && process.platform === "linux" && !process.env.DISPLAY) {
    argv = ["-a", "-s", "-screen 0 1600x900x24", GODOT, ...godotArgs];
    cmd = "xvfb-run";
  }
  const r = spawnSync(cmd, argv, {
    cwd: ROOT,
    encoding: "utf8",
    timeout: timeoutSec * 1000,
    maxBuffer: 64 * 1024 * 1024,
    env: { ...process.env, LIBGL_ALWAYS_SOFTWARE: process.env.LIBGL_ALWAYS_SOFTWARE ?? "" },
  });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.replace(ANSI, "");
  return { out, status: r.status, timedOut: r.error?.code === "ETIMEDOUT", spawnError: r.error };
}

function readJson(path, fallback) {
  return existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) : fallback;
}

function fail(msg) {
  failures.push(msg);
  console.log(`  FAIL  ${msg}`);
}

// ---- 0. Godot reachable -------------------------------------------------
const ver = godot(["--version"], { timeoutSec: 30 });
if (ver.spawnError || ver.status !== 0) {
  console.log(`CANNOT RUN GODOT: set GODOT_BIN to the Godot 4.7 executable. (${GODOT})`);
  process.exit(2);
}
console.log(`Godot ${ver.out.trim().split("\n")[0]}`);

// Import once so a fresh clone has its .godot cache; cheap when already done.
godot(["--headless", "--path", GODOT_PROJECT, "--import"], { timeoutSec: 600 });

// ---- 1. Test suites -----------------------------------------------------
console.log("\n== Test suites ==");
const baseline = readJson(BASELINE_PATH, {});
const suites = readdirSync(join(GODOT_PROJECT, "tests")).filter((f) => f.endsWith("_test.gd")).sort();
const counts = {};
for (const file of suites) {
  const r = godot(["--headless", "--path", GODOT_PROJECT, "--script", `res://tests/${file}`], { timeoutSec: 180 });
  const m = [...r.out.matchAll(/(\d+) passed, (\d+) failed/g)].pop();
  const name = file.replace(/\.gd$/, "");
  if (r.timedOut) { fail(`${name}: timed out`); continue; }
  if (!m) { fail(`${name}: no result line (script error?)\n${tail(r.out, 12)}`); continue; }
  const passed = Number(m[1]);
  const failed = Number(m[2]);
  counts[name] = passed;
  if (failed > 0 || r.status !== 0) fail(`${name}: ${failed} failed\n${tail(r.out, 15)}`);
  else if (/SCRIPT ERROR|Parse Error/.test(r.out)) fail(`${name}: script errors in output\n${tail(r.out, 12)}`);
  else if (baseline[name] !== undefined && passed < baseline[name]) fail(`${name}: ${passed} checks, baseline pins ${baseline[name]} (suite shrank)`);
  else console.log(`  ok    ${name}  ${passed}`);
}
for (const name of Object.keys(baseline)) {
  if (!(name in counts) && !failures.some((f) => f.startsWith(name))) fail(`${name}: suite in baseline but not found`);
}

// ---- 2. Bot match (the cheapest gameplay signal) ------------------------
let metrics = null;
if (!args.has("--quick")) {
  console.log("\n== Bot match ==");
  const r = godot(["--headless", "--path", GODOT_PROJECT, "--script", "res://tools/bot_match.gd"], { timeoutSec: 600 });
  if (r.timedOut) fail("bot_match: timed out");
  else {
    const num = (re) => { const x = r.out.match(re); return x ? Number(x[1]) : null; };
    metrics = {
      stall_seconds: num(/stalls\s+(\d+) seconds/),
      idle_seconds: num(/idle\s+(\d+) seconds/),
      deterministic: /DETERMINISTIC/.test(r.out) && !/DIVERGED/.test(r.out),
      winner: (r.out.match(/winner\s+(.+)/) ?? [, "unknown"])[1].trim(),
      captures: num(/captures\s+(\d+) seizures/),
      encounters_legal: (r.out.match(/(\d+) of them where a seizure was legal/) ?? [])[1] ? Number(r.out.match(/(\d+) of them where a seizure was legal/)[1]) : null,
    };
    console.log(`  ${JSON.stringify(metrics)}`);
    const budget = readJson(BUDGET_PATH, {});
    if (!metrics.deterministic) fail("bot_match: DIVERGED (two runs of the same seed differ)");
    if (budget.max_stall_seconds != null && metrics.stall_seconds != null && metrics.stall_seconds > budget.max_stall_seconds)
      fail(`bot_match: ${metrics.stall_seconds}s of stalls exceeds budget ${budget.max_stall_seconds}s`);
    if (budget.require_winner && /none/i.test(metrics.winner)) fail(`bot_match: no winner (${metrics.winner})`);
  }
}

// ---- 2b. Tick budget (hitching) -----------------------------------------
// Wall-clock, so machine-dependent: gated only on the over-budget tick count, with
// the PLAN.md P0-2 target as the limit, and p99 printed for the record.
let tick = null;
if (!args.has("--quick")) {
  console.log("\n== Tick budget ==");
  const r = godot(["--headless", "--path", GODOT_PROJECT, "--script", "res://tools/perf_probe.gd", "--", "--team-size=1"], { timeoutSec: 300 });
  const m = r.out.match(/p99 ([\d.]+)\s+worst ([\d.]+) ms\s+(\d+) of (\d+) ticks over budget/);
  if (r.timedOut) fail("perf_probe: timed out");
  else if (!m) fail(`perf_probe: no spread line\n${tail(r.out, 8)}`);
  else {
    tick = { p99_ms: Number(m[1]), worst_ms: Number(m[2]), over_budget: Number(m[3]), of: Number(m[4]) };
    console.log(`  ${JSON.stringify(tick)}`);
    const budget = readJson(BUDGET_PATH, {});
    if (budget.max_over_budget_ticks != null && tick.over_budget > budget.max_over_budget_ticks)
      fail(`perf_probe: ${tick.over_budget} of ${tick.of} ticks over the 33 ms budget, limit ${budget.max_over_budget_ticks}`);
  }
}

// ---- 3. Frames ----------------------------------------------------------
if (args.has("--frames")) {
  console.log("\n== Frames ==");
  const views = readJson(VIEWS_PATH, { views: [] }).views;
  mkdirSync(FRAMES_DIR, { recursive: true });
  for (const v of views) {
    const path = join(FRAMES_DIR, `${v.name}.png`);
    const a = ["--rendering-driver", "opengl3", "--path", GODOT_PROJECT, "--", "--capture", `--capture-delay=${v.delay ?? 3}`,
      `--capture-path=${path}`, `--capture-at=${v.at.join(",")}`];
    if (v.look) a.push(`--capture-look=${v.look.join(",")}`);
    const r = godot(a, { timeoutSec: 120, wrap: true });
    // The tool numbers shots when --capture-at is given: <name>_1.png.
    const numbered = path.replace(/\.png$/, "_1.png");
    console.log(existsSync(path) || existsSync(numbered) ? `  shot  ${existsSync(path) ? path : numbered}` : `  FAIL  ${v.name}: no frame written\n${tail(r.out, 6)}`);
    if (!existsSync(path) && !existsSync(numbered)) failures.push(`frame ${v.name}`);
  }
  console.log("  -> open each PNG with the Read tool and judge it against STYLE.md / the checklist in PLAN.md.");
}

// ---- 4. Baseline update -------------------------------------------------
if (args.has("--update-baseline")) {
  if (failures.length) { console.log("\nNot updating baseline: there are failures."); }
  else {
    writeFileSync(BASELINE_PATH, JSON.stringify(counts, null, 2) + "\n");
    if (metrics) {
      const budget = readJson(BUDGET_PATH, {});
      if (metrics.stall_seconds != null) budget.max_stall_seconds = Math.min(budget.max_stall_seconds ?? Infinity, metrics.stall_seconds);
      writeFileSync(BUDGET_PATH, JSON.stringify(budget, null, 2) + "\n");
    }
    console.log("\nBaseline and budget updated (ratchet: they only tighten).");
  }
}

console.log(failures.length ? `\nVERIFY: ${failures.length} problem(s)` : "\nVERIFY: healthy");
process.exit(failures.length ? 1 : 0);

function tail(text, n) {
  return text.trim().split("\n").slice(-n).map((l) => `        ${l}`).join("\n");
}
