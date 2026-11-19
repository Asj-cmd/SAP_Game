// Watchdog: run every 30 minutes by Windows Task Scheduler (see REMOTE_CONTROL.md). Starts the loop through
// start-loop.cmd only when: no live lock, no STOP file, PLAN.md has an open task, and the last STATUS.md state
// is not "stopped: STOP..." or "...No open tasks left". Never runs Claude. Logs one line per run to autobuild/watchdog.log.
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { liveLock, lockPath } from "./lock.mjs";
import { makeStatus } from "./status.mjs";

export function decide(root) {
  const ab = join(root, "autobuild");
  if (liveLock(lockPath(ab))) return { start: false, why: "loop already running (live lock)" };
  if (existsSync(join(root, "STOP"))) return { start: false, why: "STOP file present" };
  let plan = ""; try { plan = readFileSync(join(root, "PLAN.md"), "utf8"); } catch { return { start: false, why: "PLAN.md unreadable" }; }
  if (!/^- \[[ ~]\] /m.test(plan)) return { start: false, why: "no open tasks in PLAN.md" };
  let state = ""; try { state = (readFileSync(join(ab, "STATUS.md"), "utf8").match(/^\*\*State:\*\*\s*(.*)$/m)?.[1] ?? "").trim(); } catch { /* none yet */ }
  if (/^stopped:\s*STOP\b/i.test(state)) return { start: false, why: `last status is "${state}"` };
  if (/No open tasks left/i.test(state)) return { start: false, why: `last status is "${state}"` };
  return { start: true, why: state ? `no live loop; last status "${state}"` : "no live loop; no status yet" };
}

export const FAILURE_CAP = 3;
export const JUDGE_MS = 10 * 60_000; // a restart is a failure if the loop is not alive 10 minutes later

const stateFile = (root) => join(root, "autobuild", "watchdog.state.json");
export function readState(root) {
  try { return { failures: 0, lastStart: null, halted: false, ...JSON.parse(readFileSync(stateFile(root), "utf8")) }; } catch { return { failures: 0, lastStart: null, halted: false }; }
}
export const writeState = (root, st) => { try { writeFileSync(stateFile(root), JSON.stringify(st, null, 1) + "\n"); } catch { /* never fail */ } };
// start-loop.cmd run by hand calls this: node autobuild/watchdog.mjs --reset
export const resetState = (root) => writeState(root, { failures: 0, lastStart: null, halted: false });

const STOPPED_MSG = "stopped: repeated crash, check the terminal";

// One watchdog run. starter(root) starts the loop; writeStatus(root, state) records the give-up; both injectable.
export function run(root, starter = (r) => spawn("cmd.exe", ["/c", "start-loop.cmd", "watchdog"], { cwd: r, detached: true, stdio: "ignore" }).unref(),
  { now = Date.now(), writeStatus = defaultStatus } = {}) {
  const log = (m) => { try { appendFileSync(join(root, "autobuild", "watchdog.log"), `[${new Date(now).toISOString()}] ${m}
`); } catch { /* never fail */ } };
  const st = readState(root);
  const d = decide(root);
  const alive = d.why.startsWith("loop already running");
  if (st.halted) { log(`skip: halted after ${st.failures} crashes in a row; run start-loop.cmd by hand`); return { start: false, why: "halted" }; }

  // Judge the last restart this watchdog made.
  if (st.lastStart !== null) {
    if (alive) {
      if (now - st.lastStart >= JUDGE_MS) { st.failures = 0; st.lastStart = null; }          // still running 10 min on: success
      else { log("skip: restarted less than 10 minutes ago and still running"); return { start: false, why: "judging" }; }
    } else if (d.start) { st.failures++; st.lastStart = null; log(`restart failed: the loop is not running (failure ${st.failures} of ${FAILURE_CAP})`); }
    else st.lastStart = null;                                                                  // it ended cleanly (STOP / plan done): no failure
  }
  if (st.failures >= FAILURE_CAP) {
    st.halted = true; writeState(root, st);
    try { writeStatus(root, STOPPED_MSG); } catch (e) { log(`could not write STATUS.md: ${e.message}`); }
    log(`HALT: ${st.failures} restarts in a row failed (the loop was not alive 10 minutes later or exited within 10 minutes); not restarting again until start-loop.cmd is run by hand`);
    return { start: false, why: "halted" };
  }
  let note = "";
  if (d.start) {
    try { starter(root); st.lastStart = now; } catch (e) { note = ` (start failed: ${e.message})`; st.failures++; }
  }
  writeState(root, st);
  log(`${d.start ? "START" : "skip"}: ${d.why}${note} [failures ${st.failures}]`);
  return d;
}

function defaultStatus(root, state) {
  makeStatus({ root, log: () => {} }).write({ state, doing: "the watchdog gave up restarting the loop; read the loop's terminal", task: null, model: null, session: null });
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
  if (process.argv.includes("--reset")) resetState(root); else run(root);
}
