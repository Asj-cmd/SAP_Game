#!/usr/bin/env node
// Runs Claude Code in fresh sessions, one task each, until the plan is done, a STOP file appears,
// or progress stalls. State lives in the repo (PLAN.md, PROGRESS.md, git), not in any one session.
//
//   node autobuild/loop.mjs                         # normal
//   node autobuild/loop.mjs --max-iters 3           # trial run: do 3 sessions then stop
//   node autobuild/loop.mjs --skip-permissions      # add --dangerously-skip-permissions (throwaway clone only)
//
// Stop it any time: create a file named STOP in the repo root (it finishes the current session first).
//
// Env: MAX_TURNS (default 200)  ITER_TIMEOUT_MIN (default 90)  BACKOFF_MIN (default 30)
//      STALL_LIMIT (default 3)  GODOT_BIN (required, passed through to Claude's shell)

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const LOGS = join(HERE, "logs");
mkdirSync(LOGS, { recursive: true });

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? Number(argv[i + 1]) : d; };
const MAX_ITERS = opt("--max-iters", 200);
const MAX_TURNS = Number(process.env.MAX_TURNS ?? 200);
const ITER_TIMEOUT_MIN = Number(process.env.ITER_TIMEOUT_MIN ?? 90);
const BACKOFF_MIN = Number(process.env.BACKOFF_MIN ?? 30);
const STALL_LIMIT = Number(process.env.STALL_LIMIT ?? 3);
const LIMIT_RE = /usage limit|rate limit|limit reached|limit will reset|overloaded|too many requests|\b429\b|\b529\b|quota/i;

const sh = (cmd, args, opts = {}) =>
  spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", shell: process.platform === "win32", ...opts });
const git = (...a) => sh("git", a).stdout?.trim() ?? "";
const log = (m) => { const l = `[${new Date().toISOString()}] ${m}`; console.log(l); appendFileSync(join(LOGS, "loop.log"), l + "\n"); };
const sleep = (min) => { log(`sleeping ${min} min`); Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, min * 60_000); };
const openTasks = () => (readFileSync(join(ROOT, "PLAN.md"), "utf8").match(/^- \[[ ~]\] /gm) ?? []).length;

function writeReport(startSha, note) {
  const read = (f) => (existsSync(join(ROOT, f)) ? readFileSync(join(ROOT, f), "utf8") : "");
  const commits = git("log", "--oneline", `${startSha}..HEAD`);
  const progress = read("PROGRESS.md").split("\n").slice(0, 60).join("\n");
  const frames = git("ls-files", "-o", "-m", "--exclude-standard", "autobuild/frames") || "(see autobuild/frames)";
  writeFileSync(join(HERE, "REPORT.md"),
`# Autobuild report — ${new Date().toLocaleString()}

${note}

## Open tasks: ${openTasks()}

## Commits this run
${commits || "(none)"}

## Needs you (BLOCKED.md)
${read("BLOCKED.md") || "(nothing)"}

## Latest progress
${progress}

## Frames
${frames}
`);
}

const startSha = git("rev-parse", "HEAD");
let stalls = 0, backoffs = 0;
log(`loop start on ${git("branch", "--show-current")} @ ${startSha.slice(0, 8)}; max ${MAX_ITERS} sessions, ${MAX_TURNS} turns each`);

for (let i = 1; i <= MAX_ITERS; i++) {
  if (existsSync(join(ROOT, "STOP"))) { log("STOP file found, ending."); writeReport(startSha, "Stopped by STOP file."); break; }
  if (openTasks() === 0) { log("No open tasks left."); writeReport(startSha, "Plan complete or fully blocked."); break; }

  const before = git("rev-parse", "HEAD");
  const prompt = readFileSync(join(HERE, "PROMPT.md"), "utf8");
  const args = ["-p", "--max-turns", String(MAX_TURNS), "--output-format", "text"];
  if (flag("--skip-permissions")) args.push("--dangerously-skip-permissions");
  log(`session ${i}: starting (HEAD ${before.slice(0, 8)})`);
  const r = sh("claude", args, { input: prompt, timeout: ITER_TIMEOUT_MIN * 60_000, maxBuffer: 256 * 1024 * 1024 });
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`;
  writeFileSync(join(LOGS, `session-${String(i).padStart(3, "0")}.log`), out);

  const after = git("rev-parse", "HEAD");
  const progressed = after !== before;
  const timedOut = r.error?.code === "ETIMEDOUT";
  log(`session ${i}: exit ${r.status}${timedOut ? " (timed out)" : ""}, ${progressed ? "new commits" : "no new commits"}`);

  if (!progressed && LIMIT_RE.test(out)) {
    backoffs++;
    if (backoffs > 8) { log("Too many consecutive usage-limit backoffs, ending."); writeReport(startSha, "Ended: repeated usage limits."); break; }
    sleep(Math.min(BACKOFF_MIN * 2 ** (backoffs - 1), 180));
    i--; // a limit-blocked session does not count
    continue;
  }
  backoffs = 0;

  if (progressed) { stalls = 0; const p = sh("git", ["push", "-u", "origin", "HEAD"]); log(p.status === 0 ? "pushed" : `push failed: ${(p.stderr ?? "").trim().slice(0, 200)}`); }
  else if (++stalls >= STALL_LIMIT) { log(`${STALL_LIMIT} sessions in a row with no commits, ending.`); writeReport(startSha, "Ended: no progress for several sessions. Read autobuild/logs/."); break; }

  writeReport(startSha, `Running. Last session ${i}.`);
}
log("loop end");
