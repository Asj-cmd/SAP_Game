// Runs one `claude -p ...` session without blocking, so loop.mjs can watch it while it runs: every
// stdout line that is JSON goes to onEvent (the rate_limit_event lines tell the loop how much of the
// 5-hour limit is used), and every few seconds onTick says whether to cut the session off.
//
//   runClaude({ args, input, cwd, timeoutMs, onEvent, onTick, tickMs, command })
//     -> Promise<{ status, stdout, stderr, error, killedFor }>
//   error is { code: "ETIMEDOUT" } on a timeout, or the spawn error if claude could not start.
//   killedFor is the reason string when onTick returned { kill: "<reason>" }.
//   killTree(pid) ends a process and everything it started (Godot, node...), also on Windows.

import { spawn, spawnSync } from "node:child_process";
import { eventsFromChunk } from "./usage.mjs";

export function killTree(pid) {
  try {
    if (process.platform === "win32") spawnSync("taskkill", ["/PID", String(pid), "/T", "/F"], { windowsHide: true });
    else { try { process.kill(-pid, "SIGKILL"); } catch { process.kill(pid, "SIGKILL"); } }
  } catch { /* already gone */ }
}

export function runClaude({ args, input, cwd, timeoutMs, onEvent, onTick, tickMs = 5000, command = "claude" }) {
  return new Promise((resolve) => {
    let stdout = "", stderr = "", error = null, killedFor = null, done = false;
    const state = { rest: "" };
    const started = Date.now();
    let child;
    try {
      // On Windows claude is claude.cmd, which needs a shell: pass one command string (our args have no spaces).
      const win = process.platform === "win32";
      child = (win ? spawn(`${command} ${args.join(" ")}`, { cwd, shell: true, windowsHide: true, stdio: ["pipe", "pipe", "pipe"] })
        : spawn(command, args, { cwd, detached: true, stdio: ["pipe", "pipe", "pipe"] })); // own process group so killTree ends the lot
    } catch (e) { return resolve({ status: null, stdout, stderr, error: e, killedFor }); }
    const finish = (status) => {
      if (done) return; done = true;
      clearInterval(timer); clearTimeout(limit);
      resolve({ status, stdout, stderr, error, killedFor });
    };
    const cut = (why, err) => { if (done || killedFor || (err && error)) return; if (err) error = err; else killedFor = why; killTree(child.pid); };

    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (c) => {
      stdout += c;
      if (onEvent) for (const ev of eventsFromChunk(state, c)) { try { onEvent(ev); } catch { /* a watcher bug must not stop the session */ } }
    });
    child.stderr.on("data", (c) => { stderr += c; });
    child.on("error", (e) => { error = e; finish(null); });
    child.on("close", (code) => finish(code));
    child.stdin.on("error", () => {});
    child.stdin.end(input ?? "");

    const timer = setInterval(() => {
      if (!onTick || killedFor) return;
      let r; try { r = onTick(Date.now() - started); } catch { r = null; }
      if (r && r.kill) cut(r.kill);
    }, tickMs);
    const limit = setTimeout(() => cut(null, Object.assign(new Error("timed out"), { code: "ETIMEDOUT" })), timeoutMs);
  });
}
