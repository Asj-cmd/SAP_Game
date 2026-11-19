// node autobuild/watchdog_test.mjs: fake states, no Claude, no Godot, no real loop start.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";
import { run } from "./watchdog.mjs";
let bad = 0;
const check = (ok, l) => { if (!ok) bad++; console.log(`${ok ? "ok " : "BAD"}  ${l}`); };
const OPEN = "# plan\n- [x] **A**\n- [ ] **B**\n", DONE = "# plan\n- [x] **A**\n- [-] **B**\n";
const idle = spawn(process.execPath, ["-e", "setTimeout(()=>{},60000)"], { stdio: "ignore" });
const dead = spawn(process.execPath, ["-e", ""], { stdio: "ignore" });
await new Promise((r) => dead.on("exit", r));
function world({ plan = OPEN, lock = null, stop = false, state = null }) {
  const root = mkdtempSync(join(tmpdir(), "wd-")); mkdirSync(join(root, "autobuild"));
  writeFileSync(join(root, "PLAN.md"), plan);
  if (lock) writeFileSync(join(root, "autobuild", "loop.lock"), lock + "\n");
  if (stop) writeFileSync(join(root, "STOP"), "");
  if (state) writeFileSync(join(root, "autobuild", "STATUS.md"), `# Autobuild status\n\n**State:** ${state}\n`);
  return root;
}
const t = (name, w, want) => { let started = 0; const root = world(w); run(root, () => started++); check((started === 1) === want, `${name}: ${want ? "starts" : "does nothing"}`); const log = readFileSync(join(root, "autobuild", "watchdog.log"), "utf8"); check(log.trim().split("\n").length === 1, `   one log line: ${log.trim().slice(27)}`); };
t("live lock", { lock: idle.pid, state: "running" }, false);
t("stale lock, open tasks, crashed (state running)", { lock: dead.pid, state: "running" }, true);
t("crashed loop, no lock, open tasks", { state: "running" }, true);
t("no status yet, open tasks", {}, true);
t("STOP file present", { stop: true }, false);
t("no open tasks", { plan: DONE }, false);
t("last state stopped: STOP file", { state: "stopped: STOP file" }, false);
t("last state stopped: No open tasks left", { state: "stopped: No open tasks left" }, false);
t("waiting for limit (loop dead)", { state: "waiting for limit until Thu 3:40 AM New York time" }, true);
t("stopped by an error", { state: "stopped: error: session 3 failed" }, true);
idle.kill();
console.log(bad ? `\n${bad} WRONG` : "\nall as expected"); process.exit(bad ? 1 : 0);
