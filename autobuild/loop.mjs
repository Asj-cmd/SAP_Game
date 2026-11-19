#!/usr/bin/env node
// Runs Claude Code in fresh sessions, one task each, until the plan is done, a STOP file appears,
// or progress stalls. State lives in the repo (PLAN.md, PROGRESS.md, git), not in any one session.
//
//   node autobuild/loop.mjs                         # normal
//   node autobuild/loop.mjs --max-iters 3           # trial run: do 3 sessions then stop
//   node autobuild/loop.mjs --skip-permissions      # add --dangerously-skip-permissions (throwaway clone only)
//
// Stop it any time: create a file named STOP in the repo root (it finishes the current session first,
// and it also ends a usage-limit wait within 5 minutes).
//
// Usage limits: the loop reads the reset time from the message ("resets 1:50pm (America/New_York)",
// "resets Thu 9pm") and sleeps until 5 minutes after it; without a readable time it waits
// 30 min, 1 h, 2 h, then 3 h at a time. Limit waits are not sessions and are not "no commit" stalls.
// It gives up only after 8 days of waiting in a row (enough for the weekly limit).
//
// Sign-in / network errors ("Failed to authenticate", 403, Cloudflare, ECONNRESET, API Error 5xx...):
// waits 15 min, 30 min, then 60 min at a time and retries; these are not sessions or stalls either.
// After 6 such waits in a row (about 4.75 h) it stops and tells you to run claude.cmd and /login.
//
// Planner and worker models (all optional; unset = Claude's default model):
//   PLANNER_MODEL  e.g. "opus": before a worker session, if autobuild/BRIEF.md has no section for the
//                  first open task, one short planner session (PLANNER_PROMPT.md, 40 turns) writes
//                  briefs for the next 3 tasks. A planner session is not a worker session and does not
//                  count toward the stall limit. It is tried at most once per task per run.
//   WORKER_MODEL   e.g. "opus": the model for worker sessions (CLAUDE_MODEL still works the same way).
//   A task line in PLAN.md that contains "(worker: fable)" runs its worker session with --model fable
//   instead. If Fable's own limit is hit, or it says "Fable 5.2 requires usage credits", the loop
//   uses WORKER_MODEL (or the default) for every task for the rest of the run, with no wait (and it
//   is not mistaken for a failed start). If the planner model says that, planning is skipped for the
//   rest of the run, and the log says why.
//   If the worker model hits its OWN limit ("Opus limit reached") the workers switch to sonnet for the
//   rest of the run, with no wait. If the planner model hits its own limit, planning is skipped for the
//   rest of the run. Limits that are not model-specific (5-hour, weekly) wait as above.
//
// Usage guard (usage.mjs, runner.mjs): the loop reads the 5-hour usage from the rate_limit_event lines of
// `claude -p --output-format stream-json --verbose`. At USAGE_STOP_PCT (default 75) it starts no new
// session and asks a running one to commit and finish (a hook, autobuild/wrap_hook.mjs, shows the session
// the file autobuild/WRAP_UP). A session that has not finished by USAGE_HARD_PCT (default 80) or
// WRAP_UP_MIN minutes (default 15) is cut off, and the loop commits and pushes what it left. Then the loop
// waits for the 5-hour reset (+3 min) and carries on by itself. USAGE_STOP_PCT=0 turns the guard off.
// The weekly limit: when it is really hit, the loop waits for its stated reset (up to 8 days) and restarts.
//
// Lock: autobuild/loop.lock holds this process's PID while it runs (start-loop.cmd, watchdog.mjs read it).
//
// Status heartbeat: at loop start, each worker / planner session start and end, each wait, a STOP, an
// error stop and "No open tasks left", the loop writes autobuild/STATUS.md (state, task, model, session,
// last commit, time) and commits and pushes that file ALONE as "status: <state>" (status.mjs). If only the
// time would change, nothing is written. A failure to write or push is logged in one line and ignored.
//
// Env: MAX_TURNS (default 200)  ITER_TIMEOUT_MIN (default 120)  BACKOFF_MIN (default 30)
//      USAGE_STOP_PCT (75)  USAGE_HARD_PCT (80)  WRAP_UP_MIN (15)
//      STALL_LIMIT (default 3)  PLANNER_MODEL  WORKER_MODEL / CLAUDE_MODEL  PLANNER_TIMEOUT_MIN (default 25)
//      GODOT_BIN (required, passed through to Claude's shell)

import { spawnSync } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { isLimitMessage, planLimitWait, isConnectionProblem, connectionWaitMin, MAX_CONNECTION_WAITS, limitAction } from "./limits.mjs";
import { firstOpenTaskId, hasBriefFor, briefHeadings, pickWorkerModel } from "./planning.mjs";
import { isModelLimit, modelFamily, whyModelLimit, taggedFallback } from "./limits.mjs";
import { makeStatus, nyLabel } from "./status.mjs";
import { UsageTracker, readingFromEvent, textFromStream, preflight, monitorDecision, usageResetAt, pctOf, MIN, RESET_SLACK_MS } from "./usage.mjs";
import { runClaude } from "./runner.mjs";
import { liveLock, lockPath, writeLock, removeOwnLock } from "./lock.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(HERE, "..");
const LOGS = join(HERE, "logs");
mkdirSync(LOGS, { recursive: true });

const argv = process.argv.slice(2);
const flag = (n) => argv.includes(n);
const opt = (n, d) => { const i = argv.indexOf(n); return i >= 0 ? Number(argv[i + 1]) : d; };
const MAX_ITERS = opt("--max-iters", 200);
const MAX_TURNS = Number(process.env.MAX_TURNS ?? 200);
const ITER_TIMEOUT_MIN = Number(process.env.ITER_TIMEOUT_MIN ?? 120);
const PLANNER_TIMEOUT_MIN = Number(process.env.PLANNER_TIMEOUT_MIN ?? 25);
const PLANNER_TURNS = 40;
const BACKOFF_MIN = Number(process.env.BACKOFF_MIN ?? 30);
const STALL_LIMIT = Number(process.env.STALL_LIMIT ?? 3);
const USAGE_STOP_PCT = Number(process.env.USAGE_STOP_PCT ?? 75); // 0 = guard off
const USAGE_HARD_PCT = Number(process.env.USAGE_HARD_PCT ?? 80);
const WRAP_UP_MIN = Number(process.env.WRAP_UP_MIN ?? 15);
const WRAP_FILE = join(HERE, "WRAP_UP");
const STREAM = ["--output-format", "stream-json", "--verbose"]; // events as they happen (usage), see usage.mjs
const TRUST_RE = /Ignoring\b.*\bpermissions?\b|has not been trusted/i;
const MAX_LIMIT_WAIT_MS = 8 * 24 * 60 * 60_000; // weekly limit plus a day of slack
const FALLBACK_WORKER = "sonnet";
const BRIEF = join(HERE, "BRIEF.md");
// null = the default model. workerModel becomes "sonnet" if its own limit is hit; plannerModel becomes
// null (no planning) if its own limit is hit.
let workerModel = process.env.WORKER_MODEL?.trim() || process.env.CLAUDE_MODEL?.trim() || null;
let plannerModel = process.env.PLANNER_MODEL?.trim() || null;
const plannerTried = new Set(); // task ids the planner has already had its one go at in this run
const tagOff = new Set(); // "(worker: X)" tags whose model hit its own limit: those tasks use workerModel

const sh = (cmd, args, opts = {}) =>
  spawnSync(cmd, args, { cwd: ROOT, encoding: "utf8", shell: process.platform === "win32", ...opts });
const git = (...a) => sh("git", a).stdout?.trim() ?? "";
// git without a shell: arguments with spaces (commit messages) stay whole.
const gitx = (...a) => spawnSync("git", a, { cwd: ROOT, encoding: "utf8" });
const log = (m) => { const l = `[${new Date().toISOString()}] ${m}`; console.log(l); appendFileSync(join(LOGS, "loop.log"), l + "\n"); };
const when = (ms) => new Date(ms).toLocaleString("en-US", { weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" });
// Sleeps in 5-minute steps against the real clock, so a PC that slept still wakes on time and a
// STOP file ends the wait. Returns true when stopped by STOP.
function sleepUntil(untilMs) {
  const cell = new Int32Array(new SharedArrayBuffer(4));
  for (let left = untilMs - Date.now(); left > 0; left = untilMs - Date.now()) {
    if (existsSync(join(ROOT, "STOP"))) return true;
    Atomics.wait(cell, 0, 0, Math.min(left, 5 * 60_000));
  }
  return existsSync(join(ROOT, "STOP"));
}
const planText = () => readFileSync(join(ROOT, "PLAN.md"), "utf8");
const briefText = () => (existsSync(BRIEF) ? readFileSync(BRIEF, "utf8") : "");
const openTasks = () => (planText().match(/^- \[[ ~]\] /gm) ?? []).length;

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
// The lock file holds our PID so start-loop.cmd and the watchdog know a loop is running. Removed on every
// exit (a crash or a power cut leaves it behind; a dead PID counts as stale).
const LOCK = lockPath(HERE);
if (liveLock(LOCK)) { console.log("Loop already running (autobuild/loop.lock holds a live PID). Not starting a second one."); process.exit(0); }
writeLock(LOCK);
process.on("exit", () => removeOwnLock(LOCK));
for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(sig, () => process.exit(130));
const status = makeStatus({ root: ROOT, log });
let cur = { task: null, model: null, session: null, doing: "loop start" }; // what the status file says is going on
const setStatus = (state, extra = {}) => { cur = { ...cur, ...extra }; status.write({ state, ...cur, usage: tracker.summary() }); };
let endReason = null; // why the loop stopped, for the final status
const tracker = new UsageTracker();
const GUARD = USAGE_STOP_PCT > 0;

// Runs one Claude session and watches it: usage events update the tracker, and at the stop line the
// session is asked to wrap up (WRAP_UP file, shown by the hook), later cut off if it does not finish.
async function claudeSession(label, args, input, timeoutMin) {
  let wrapSince = null, wrapWhy = null;
  const onTick = () => {
    if (!GUARD) return null;
    const d = monitorDecision(tracker, { stopPct: USAGE_STOP_PCT, hardPct: USAGE_HARD_PCT, wrapMin: WRAP_UP_MIN, wrapSince });
    if (d.action === "wrap" && wrapSince === null) {
      wrapSince = Date.now(); wrapWhy = d.why;
      try { writeFileSync(WRAP_FILE, `USAGE WRAP-UP (from the loop): ${d.why}. Start nothing new. Commit what you have NOW as "<task> (part): ..." (no verify; do not push, the loop pushes), put one line at the top of PROGRESS.md saying what is unfinished, then end your reply in one line.\n`); } catch { /* the hook is best effort; the loop cuts the session off later */ }
      log(`${label}: ${d.why}: asked it to commit and finish (cut off after ${WRAP_UP_MIN} min or at ${USAGE_HARD_PCT}%)`);
      setStatus("running", { doing: `${label} wrapping up: ${d.why}` });
    } else if (d.action === "kill") {
      log(`${label}: cutting it off: ${d.why}`);
      return { kill: d.why };
    }
    return null;
  };
  const r = await runClaude({
    args, input, cwd: ROOT, timeoutMs: timeoutMin * 60_000, onTick, tickMs: 5000,
    onEvent: (ev) => { tracker.update(readingFromEvent(ev)); },
  });
  try { unlinkSync(WRAP_FILE); } catch { /* none */ }
  return { ...r, wrapped: wrapSince !== null, wrapWhy };
}
// What `--output-format text` would have printed, for the limit / sign-in checks below.
const decodedOut = (r) => `${textFromStream(r.stdout)}\n${r.stderr ?? ""}${r.error && r.error.code !== "ETIMEDOUT" ? `\n[could not start claude: ${r.error.message}]` : ""}`;
const writeLogs = (name, r, out) => { writeFileSync(join(LOGS, name), out); try { writeFileSync(join(LOGS, name.replace(/\.log$/, ".jsonl")), r.stdout ?? ""); } catch { /* optional */ } };

// One tiny call to learn the usage before the first session (stream-json prints it with the first reply).
async function probeUsage() {
  if (!GUARD) return;
  const r = await runClaude({
    args: ["-p", "--max-turns", "1", ...STREAM, "--model", "sonnet"], input: "Reply with the single word OK",
    cwd: tmpdir(), timeoutMs: 3 * MIN, onEvent: (ev) => { tracker.update(readingFromEvent(ev)); },
  });
  const sum = tracker.summary();
  log(sum ? `usage now: ${sum}; the loop starts no session at ${USAGE_STOP_PCT}% of the 5-hour limit` : `usage: could not read it (exit ${r.status}); relying on the limit messages`);
}

// Commit and keep what a cut-off session left, so nothing is lost and the next session sees a clean tree.
function saveLeftovers(label, why) {
  try {
    if (!gitx("status", "--porcelain").stdout.trim()) return false;
    const pf = join(ROOT, "PROGRESS.md");
    if (existsSync(pf)) {
      let t = readFileSync(pf, "utf8"); const nl = t.includes("\r\n") ? "\r\n" : "\n";
      const i = t.indexOf("## 20");
      const note = `> **UNFINISHED (${cur.task ?? label}):** ${label} was stopped by the loop (${why}) and the loop committed its files as they were. Look at the last commit, finish or fix it first, and run verify once at the end.` + nl + nl;
      if (i >= 0) writeFileSync(pf, t.slice(0, i) + note + t.slice(i));
    }
    gitx("add", "-A");
    const c = gitx("commit", "-q", "-m", `${cur.task ?? label} (part): stopped by the usage guard (${why}); saved by the loop\n\nCo-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`);
    if (c.status !== 0) throw new Error((c.stderr || c.stdout || "").trim().slice(0, 150));
    log(`${label}: committed what it left (${why})`);
    return true;
  } catch (e) { log(`${label}: could not save leftovers: ${String(e.message ?? e).slice(0, 200)}`); return false; }
}

// Wait for the 5-hour reset (STOP file ends it), then carry on by itself. "retry" or "stopped".
function waitForUsageReset(until, pct, why) {
  log(`usage guard: ${pct !== null ? pct + "% of the 5-hour limit used" : "stopping"} (${why}). Waiting until ${when(until)} (this PC's time), then carrying on by itself. Create a STOP file to end the wait.`);
  writeReport(startSha, `Paused by the usage guard (${why}); resumes after ${when(until)}.`);
  setStatus(`waiting for limit until ${nyLabel(until)}`, { doing: `paused at ${pct ?? "?"}% of the 5-hour limit (${why}); restarts by itself after the reset` });
  const stopped = sleepUntil(until);
  tracker.clear("five");
  if (stopped) { log("STOP file found during the usage wait, ending."); writeReport(startSha, "Stopped by STOP file (during a usage wait)."); endReason = "STOP file (during a usage wait)"; return "stopped"; }
  log("usage wait over, carrying on");
  return "retry";
}
// After a session was wrapped up or cut off by the guard: save, push, wait. { res, progressed }
function usageStop(label, r, before) {
  const why = r.killedFor ?? r.wrapWhy ?? "usage guard";
  saveLeftovers(label, why);
  const progressed = git("rev-parse", "HEAD") !== before;
  if (progressed) { const p = sh("git", ["push", "-u", "origin", "HEAD"]); log(p.status === 0 ? "pushed" : `push failed: ${(p.stderr ?? "").trim().slice(0, 200)}`); }
  const f = tracker.fiveHour();
  const until = f?.resetsAt ? f.resetsAt * 1000 + RESET_SLACK_MS : Date.now() + 30 * MIN;
  return { res: waitForUsageReset(until, f ? pctOf(f.utilization) : null, why), progressed };
}
let stalls = 0, attempt = 0;
let limitWaitedMs = 0, fallbackStep = 0, lastTarget = null; // reset whenever a session runs without hitting a limit
let connectionWaits = 0; // sign-in/network waits in a row; reset whenever Claude gets through

// A usage limit that is not specific to a model: wait for the reset. `label` names who hit it
// ("session 4", "planner"); `last` is the last finished session number, for the report.
// Returns "retry" (waited, try again), "stopped" (STOP file) or "giveup" (would pass 8 days).
function waitForLimit(out, label, last) {
  const now = Date.now();
  const plan = planLimitWait({ text: out, now, lastTarget, step: fallbackStep + 1, backoffMin: BACKOFF_MIN });
  if (plan.target === null) fallbackStep++; else lastTarget = plan.target;
  const exact = usageResetAt(tracker, now); // the stream told us which window is full and when it resets
  if (exact) { plan.until = exact + RESET_SLACK_MS; plan.source = "the usage events"; }
  const waitMs = plan.until - now;
  if (limitWaitedMs + waitMs > MAX_LIMIT_WAIT_MS) {
    const msg = `Usage limit: already waited ${(limitWaitedMs / 3_600_000).toFixed(1)} h in a row and the next wait ` +
      `(until ${when(plan.until)}) would pass 8 days. Stopping. Check your plan's limits, then start the loop again.`;
    log(msg);
    writeReport(startSha, `Ended: ${msg}`);
    endReason = "error: usage limit wait would pass 8 days";
    return "giveup";
  }
  log(`${label}: usage limit (${plan.source}). Not counted as a session.`);
  log(`waiting until ${when(plan.until)} (this PC's time; ${(waitMs / 3_600_000).toFixed(1)} h). Create a STOP file to end the wait.`);
  writeReport(startSha, `Waiting for the usage limit to reset: until ${when(plan.until)}. Last session ${last}.`);
  setStatus(`waiting for limit until ${nyLabel(plan.until)}`, { doing: `waiting after ${label} hit a usage limit` });
  const stopped = sleepUntil(plan.until);
  limitWaitedMs += Date.now() - now;
  if (stopped) { log("STOP file found during the usage-limit wait, ending."); writeReport(startSha, "Stopped by STOP file (during a usage-limit wait)."); endReason = "STOP file (during a usage-limit wait)"; return "stopped"; }
  log("usage-limit wait over, trying again");
  return "retry";
}

// A sign-in or network problem: wait 15, 30, 60, 60... minutes, up to 6 times in a row.
// Returns "retry", "stopped" or "giveup".
function waitForConnection(label, logName, last) {
  if (connectionWaits >= MAX_CONNECTION_WAITS) {
    const msg = `${label}: Claude still cannot connect or sign in after ${MAX_CONNECTION_WAITS} waits in a row ` +
      `(about 4.75 hours). Stopping. Fix: open PowerShell in this folder, run claude.cmd, type /login and sign in, ` +
      `type /exit, then start the loop again. Full text in autobuild/logs/${logName}.`;
    log(msg);
    writeReport(startSha, `Ended: ${msg}`);
    endReason = "error: Claude cannot connect or sign in (run claude.cmd and /login)";
    return "giveup";
  }
  const mins = connectionWaitMin(connectionWaits++);
  const until = Date.now() + mins * 60_000;
  log(`${label}: connection/sign-in problem (wait ${connectionWaits} of ${MAX_CONNECTION_WAITS}). Not counted as a session.`);
  log(`connection/sign-in problem, waiting until ${when(until)} (this PC's time; ${mins} min). Create a STOP file to end the wait.`);
  writeReport(startSha, `Connection/sign-in problem: waiting until ${when(until)}, then retrying. Last session ${last}.`);
  setStatus(`waiting for connection until ${nyLabel(until)}`, { doing: `waiting after ${label} had a connection or sign-in problem` });
  if (sleepUntil(until)) { log("STOP file found during the connection wait, ending."); writeReport(startSha, "Stopped by STOP file (during a connection wait)."); endReason = "STOP file (during a connection wait)"; return "stopped"; }
  log("connection wait over, trying again");
  return "retry";
}

// One short planner session: writes briefs for the next 3 open tasks into autobuild/BRIEF.md.
// Never throws and never counts as a stall. Returns "done" (carry on to the worker), "retry" (it waited
// out a limit or a connection problem; plan again) or "stop" (STOP file, or gave up waiting).
async function runPlanner(taskId, last) {
  const promptFile = join(HERE, "PLANNER_PROMPT.md");
  if (!existsSync(promptFile)) {
    log("planner: autobuild/PLANNER_PROMPT.md is missing, skipping planning for the rest of this run");
    plannerModel = null;
    return "done";
  }
  setStatus("running", { doing: "planner session", task: taskId, model: plannerModel, session: `before session ${last + 1}` });
  const before = git("rev-parse", "HEAD");
  const args = ["-p", "--max-turns", String(PLANNER_TURNS), ...STREAM, "--model", plannerModel];
  if (flag("--skip-permissions")) args.push("--dangerously-skip-permissions");
  log(`planner: starting (model ${plannerModel}, first open task ${taskId}, HEAD ${before.slice(0, 8)})`);
  const started = Date.now();
  const r = await claudeSession("planner", args, readFileSync(promptFile, "utf8"), PLANNER_TIMEOUT_MIN);
  const seconds = (Date.now() - started) / 1000;
  const out = decodedOut(r);
  const logName = `planner-${String(++attempt).padStart(3, "0")}.log`;
  writeLogs(logName, r, out);
  const progressed = git("rev-parse", "HEAD") !== before;
  const failed = r.status !== 0 || Boolean(r.error);
  log(`planner: exit ${r.status}${r.error?.code === "ETIMEDOUT" ? " (timed out)" : ""} after ${seconds.toFixed(1)} s, ${progressed ? "new commit" : "no new commit"}`);

  if (r.wrapped || r.killedFor) return usageStop("planner", r, before).res === "retry" ? "retry" : "stop";
  if (!progressed && isLimitMessage(out)) {
    const act = limitAction(out, { role: "planner", model: plannerModel, fallback: FALLBACK_WORKER });
    if (act.kind === "skip-planner") {
      log(`planner: ${act.family} ${act.why}, skipping planning for the rest of this run (no briefs from now on; workers carry on). Not counted as a session.`);
      plannerModel = null;
      return "done";
    }
    connectionWaits = 0;
    return waitForLimit(out, "planner", last) === "retry" ? "retry" : "stop";
  }
  if (failed && !progressed && isConnectionProblem(out)) {
    return waitForConnection("planner", logName, last) === "retry" ? "retry" : "stop";
  }

  plannerTried.add(taskId); // one go per task per run, whatever came of it
  setStatus("running", { doing: `planner session ended (exit ${r.status}, ${progressed ? "new commit" : "no new commit"})` });
  limitWaitedMs = 0; fallbackStep = 0; lastTarget = null; connectionWaits = 0;
  const lines = out.split(/\r?\n/).filter((l) => l.trim() !== "");
  for (const l of lines.slice(-4)) log(`  planner | ${l}`);
  if (progressed) { const p = sh("git", ["push", "-u", "origin", "HEAD"]); log(p.status === 0 ? "planner: pushed" : `planner: push failed: ${(p.stderr ?? "").trim().slice(0, 200)}`); }
  const ids = briefHeadings(briefText());
  log(hasBriefFor(briefText(), taskId)
    ? `planner: done. BRIEF.md has sections for ${ids.join(", ")}`
    : `planner: done, but BRIEF.md has no section for ${taskId} (the worker runs without one). Full text in autobuild/logs/${logName}`);
  return "done";
}

log(`loop start on ${git("branch", "--show-current")} @ ${startSha.slice(0, 8)}; max ${MAX_ITERS} sessions, ${MAX_TURNS} turns each; ` +
  `planner ${plannerModel ?? "off"}, workers ${workerModel ?? "default model"}`);
await probeUsage();
setStatus("running", { doing: "loop started", task: firstOpenTaskId(planText()), model: workerModel ?? "default" });

for (let i = 1; i <= MAX_ITERS; i++) {
  if (existsSync(join(ROOT, "STOP"))) { log("STOP file found, ending."); writeReport(startSha, "Stopped by STOP file."); endReason = "STOP file"; break; }
  if (openTasks() === 0) { log("No open tasks left."); writeReport(startSha, "Plan complete or fully blocked."); endReason = "No open tasks left"; break; }

  // The 5-hour guard: no new session while usage is at the stop line.
  if (GUARD) {
    const pf = preflight(tracker, { stopPct: USAGE_STOP_PCT });
    if (pf.wait) {
      if (waitForUsageReset(pf.until, pf.pct, `not starting a session at ${pf.pct}%`) === "retry") { i--; continue; }
      break;
    }
  }

  // Planner first, when the first open task has no brief yet.
  if (plannerModel) {
    const taskId = firstOpenTaskId(planText());
    if (taskId && !hasBriefFor(briefText(), taskId) && !plannerTried.has(taskId)) {
      const res = await runPlanner(taskId, i - 1);
      if (res === "retry") { i--; continue; }
      if (res === "stop") break;
    }
  }

  const prompt = readFileSync(join(HERE, "PROMPT.md"), "utf8");
  const args = ["-p", "--max-turns", String(MAX_TURNS), ...STREAM];
  // The model for this session: a "(worker: fable)" tag on the first open task, else WORKER_MODEL.
  const pick = pickWorkerModel(planText(), { workerModel, tagOff });
  // Status first, THEN read HEAD: the status commit must not look like the session's own commit.
  setStatus("running", { doing: "worker session", task: firstOpenTaskId(planText()), model: pick.model ?? "default", session: i });
  const before = git("rev-parse", "HEAD");
  if (pick.model) args.push("--model", pick.model);
  if (flag("--skip-permissions")) args.push("--dangerously-skip-permissions");
  log(`session ${i}: starting (HEAD ${before.slice(0, 8)}, model ${pick.model ?? "default"}${pick.tagged ? ", tagged in PLAN.md" : ""})`);
  const started = Date.now();
  const r = await claudeSession(`session ${i}`, args, prompt, ITER_TIMEOUT_MIN);
  const seconds = (Date.now() - started) / 1000;
  const out = decodedOut(r);
  // Numbered per launch, not per session, so a limit-blocked launch keeps its own log.
  const logName = `session-${String(++attempt).padStart(3, "0")}.log`;
  writeLogs(logName, r, out);

  const after = git("rev-parse", "HEAD");
  const progressed = after !== before;
  const timedOut = r.error?.code === "ETIMEDOUT";
  const failed = r.status !== 0 || Boolean(r.error);
  log(`session ${i}: exit ${r.status}${timedOut ? " (timed out)" : ""} after ${seconds.toFixed(1)} s, ${progressed ? "new commits" : "no new commits"}`);

  // A failed session with nothing to show: print why, right here in the terminal.
  if (failed && !progressed) {
    const lines = out.split(/\r?\n/).filter((l) => l.trim() !== "");
    log(`session ${i} failed. Last ${Math.min(15, lines.length)} lines of its output (full text: autobuild/logs/${logName}):`);
    for (const l of (lines.length ? lines.slice(-15) : ["(no output at all)"])) log(`  | ${l}`);
  }

  // Claude ignored the project's permission list (folder not trusted): every real action needs an
  // approval nobody is there to give, so further sessions would waste time. Stop now, whatever the exit code.
  const trustLines = out.split(/\r?\n/).filter((l) => TRUST_RE.test(l));
  if (trustLines.length) {
    for (const l of trustLines.slice(0, 5)) log(`  | ${l.trim()}`);
    const msg = `Session ${i}: Claude ignored the permission list in .claude/settings.json (this folder is not trusted), ` +
      `so it could not run commands or edit files. Stopping the loop. Fix: open PowerShell, cd to this folder, run "claude", ` +
      `choose "Yes, proceed" on the trust question, type /exit, then start the loop again.` +
      (progressed ? " Note: this session did make commits; they were NOT pushed." : "") +
      ` Full text in autobuild/logs/${logName}.`;
    log(msg);
    writeReport(startSha, `Ended: ${msg}`);
    endReason = "error: Claude ignored the permission list (folder not trusted; run claude once and choose Yes, proceed)";
    break;
  }

  // The 5-hour guard stopped or wrapped up this session: save what it left, push, wait for the reset.
  if (r.wrapped || r.killedFor) {
    const u = usageStop(`session ${i}`, r, before);
    if (u.res !== "retry") break; // waitForUsageReset set endReason
    if (u.progressed) stalls = 0; else i--; // a session that made nothing does not count
    continue;
  }

  // Usage limit: checked BEFORE the fast-failure rule, so a limit is never treated as a broken install.
  // The worker model's own limit switches the workers to sonnet at once; any other limit waits for the
  // reset. Neither is a session or a "no commits" stall.
  if (!progressed && isLimitMessage(out)) {
    connectionWaits = 0; // a limit message means Claude did connect and sign in
    // A task tagged "(worker: fable)" whose Fable limit is hit: use WORKER_MODEL from now on, no wait.
    if (pick.tagged && isModelLimit(out, pick.model)) {
      tagOff.add(pick.model);
      // If WORKER_MODEL is the very model that just failed, use sonnet rather than try it again.
      workerModel = taggedFallback({ tag: pick.model, workerModel, fallback: FALLBACK_WORKER });
      log(`session ${i}: ${modelFamily(pick.model)} ${whyModelLimit(out)}, using ${workerModel ?? "the default model"} for every task for the rest of this run (no wait, not a failed start). Not counted as a session.`);
      i--; // the same session number runs again, at once
      continue;
    }
    const act = limitAction(out, { role: "worker", model: pick.model, fallback: FALLBACK_WORKER });
    if (act.kind === "switch-worker") {
      log(`session ${i}: ${act.family} ${act.why}, switching workers to ${act.to} for the rest of this run. Not counted as a session.`);
      workerModel = act.to;
      i--; // the same session number runs again, at once
      continue;
    }
    const w = waitForLimit(out, `session ${i}`, i - 1);
    if (w === "retry") { i--; continue; } // the same session number runs again
    break; // waitForLimit set endReason
  }

  // Sign-in or network problem: also checked BEFORE the fast-failure rule. Wait and retry; the wait
  // is not a session and not a "no commits" stall.
  if (failed && !progressed && isConnectionProblem(out)) {
    const w = waitForConnection(`Session ${i}`, logName, i - 1);
    if (w === "retry") { i--; continue; }
    break; // waitForConnection set endReason
  }
  limitWaitedMs = 0; fallbackStep = 0; lastTarget = null; connectionWaits = 0;

  // Failing in seconds means claude never really started (not installed, broken install, not
  // signed in, bad flag). Retrying cannot fix that, so stop and say so.
  if (failed && !progressed && seconds < 10) {
    const msg = `Session ${i} failed after only ${seconds.toFixed(1)} s, so Claude probably did not start at all ` +
      `(check that "claude --version" works in this terminal and that you are signed in). ` +
      `Stopping instead of retrying. Reason above, full text in autobuild/logs/${logName}.`;
    log(msg);
    writeReport(startSha, `Ended: ${msg}`);
    endReason = `error: session ${i} failed after ${seconds.toFixed(1)} s (Claude probably did not start)`;
    break;
  }

  setStatus("running", { doing: `worker session ${i} ended (exit ${r.status}${timedOut ? ", timed out" : ""}, ${progressed ? "new commits" : "no new commits"})` });
  if (progressed) { stalls = 0; const p = sh("git", ["push", "-u", "origin", "HEAD"]); log(p.status === 0 ? "pushed" : `push failed: ${(p.stderr ?? "").trim().slice(0, 200)}`); }
  else if (++stalls >= STALL_LIMIT) { log(`${STALL_LIMIT} sessions in a row with no commits, ending.`); writeReport(startSha, "Ended: no progress for several sessions. Read autobuild/logs/."); endReason = `error: ${STALL_LIMIT} sessions in a row with no commits`; break; }

  writeReport(startSha, `Running. Last session ${i}.`);
}
setStatus(`stopped: ${endReason ?? "reached the session limit (--max-iters)"}`, { doing: "loop ended" });
log("loop end");
