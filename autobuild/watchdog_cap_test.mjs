// node autobuild/watchdog_cap_test.mjs: the crash cap, with fake states and a fake clock. No Claude, no Godot, no real loop.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { run, readState, resetState } from "./watchdog.mjs";
let bad = 0;
const check = (ok, l) => { if (!ok) bad++; console.log(`${ok ? "ok " : "BAD"}  ${l}`); };
const MIN = 60_000;
const idle = spawn(process.execPath, ["-e", "setTimeout(()=>{},60000)"], { stdio: "ignore" });
const root = mkdtempSync(join(tmpdir(), "wdcap-")); mkdirSync(join(root, "autobuild"));
writeFileSync(join(root, "PLAN.md"), "# plan\n- [ ] **B**\n");
const lock = join(root, "autobuild", "loop.lock");
const setAlive = (on) => { if (on) writeFileSync(lock, idle.pid + "\n"); else writeFileSync(lock, "999999\n"); };
let starts = 0, statusWritten = null, t = Date.parse("2026-11-20T00:00:00Z");
const go = (adv = 30) => { t += adv * MIN; return run(root, () => starts++, { now: t, writeStatus: (r, s) => { statusWritten = s; } }); };

console.log("== 1 failure restarts ==");
setAlive(false); go(); check(starts === 1 && readState(root).failures === 0, "crashed loop: restarted (1 start)");
setAlive(false); go(); check(starts === 2 && readState(root).failures === 1, "restart did not survive: failure 1, restarted again");
console.log("\n== a restart that survives 10 minutes resets the count ==");
setAlive(true); go(); check(readState(root).failures === 0 && starts === 2, "alive 30 min later: count back to 0, no new start");
console.log("\n== 3 failures stop ==");
setAlive(false); go(); const s3 = starts; // restart (lastStart set)
setAlive(false); go(); setAlive(false); go(); // failure 1, restart; failure 2, restart
check(readState(root).failures === 2 && !readState(root).halted, "2 failures: still restarting");
setAlive(false); const before = starts; go();
check(readState(root).halted && starts === before && readState(root).failures === 3, "3rd failure: halted, no restart");
check(statusWritten === "stopped: repeated crash, check the terminal", `STATUS.md state: "${statusWritten}"`);
check(/HALT: 3 restarts/.test(readFileSync(join(root, "autobuild", "watchdog.log"), "utf8")), "the reason is in watchdog.log");
go(); go(); check(starts === before, "later runs do nothing");
console.log("\n== a manual start resets ==");
resetState(root); check(readState(root).failures === 0 && !readState(root).halted, "reset by start-loop.cmd: count 0, not halted");
setAlive(false); go(); check(starts === before + 1, "the watchdog restarts again after a manual reset");
console.log("\n== STOP does not restart, and is not a failure ==");
resetState(root); setAlive(false); go(); // restart, pending judgement
writeFileSync(join(root, "STOP"), ""); setAlive(false); const b2 = starts; go();
check(starts === b2 && readState(root).failures === 0, "STOP: no restart, no failure counted");
console.log("");
console.log("== a loop that exits within 10 minutes of its start ==");
unlinkSync(join(root, "STOP")); resetState(root); setAlive(false); go();
const b3 = starts;
setAlive(false); go(5); // 5 minutes later it is already dead
check(readState(root).failures === 1 && starts === b3 + 1, "dead 5 minutes after a restart: counted as a failure, restarted");
idle.kill();
console.log(bad ? bad + " WRONG" : "all as expected"); process.exit(bad ? 1 : 0);
