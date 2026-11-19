// Watchdog: run every 30 minutes by Windows Task Scheduler (see REMOTE_CONTROL.md). Starts the loop through
// start-loop.cmd only when: no live lock, no STOP file, PLAN.md has an open task, and the last STATUS.md state
// is not "stopped: STOP..." or "...No open tasks left". Never runs Claude. Logs one line per run to autobuild/watchdog.log.
import { appendFileSync, existsSync, readFileSync } from "node:fs";
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { liveLock, lockPath } from "./lock.mjs";

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

export function run(root, starter = (r) => spawn("cmd.exe", ["/c", "start-loop.cmd"], { cwd: r, detached: true, stdio: "ignore" }).unref()) {
  const d = decide(root);
  let note = "";
  if (d.start) { try { starter(root); } catch (e) { note = ` (start failed: ${e.message})`; } }
  try { appendFileSync(join(root, "autobuild", "watchdog.log"), `[${new Date().toISOString()}] ${d.start ? "START" : "skip"}: ${d.why}${note}\n`); } catch { /* never fail */ }
  return d;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) run(resolve(dirname(fileURLToPath(import.meta.url)), ".."));
