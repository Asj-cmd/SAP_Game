// Status heartbeat for loop.mjs: writes autobuild/STATUS.md, commits it alone and pushes it, so you can
// see from anywhere whether the loop is running, waiting for a usage limit, or stopped, and why.
//
//   makeStatus({ root, log, push })   returns { write(fields) }
//   write({ state, task, model, session, doing })
//       state    "running" | "waiting for limit until <time>" | "stopped: <reason>" (free text)
//       task     task id ("PT4-8") or null; model ("opus"), session number, doing ("worker session")
//
// Rules (set by the user):
//   - Called at events only (no timer): loop start, worker / planner start and end, a limit wait,
//     STOP, an error stop, "No open tasks left".
//   - STATUS.md is committed ALONE ("status: <state>", git commit --only on that one path), never with game
//     work, and pushed. If the only change would be the time, nothing is written or committed (so the
//     working tree stays clean).
//   - It must never stop or slow the loop: every failure is caught and logged as one line; git calls have
//     a short timeout.
//   - The commit subject "status: ..." is skipped when looking for the "last commit" shown in the file.
//   - Call it BEFORE the loop reads HEAD at a session start, and AFTER it reads HEAD at a session end,
//     so a status commit is never mistaken for the session's own commit.

import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";

export const STATUS_PATH = "autobuild/STATUS.md";
const NY = "America/New_York";
const GIT_TIMEOUT_MS = 30_000;

// "Thu, Nov 19, 12:41 AM" in New York, from epoch ms.
export const nyTime = (ms) =>
  new Intl.DateTimeFormat("en-US", { timeZone: NY, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }).format(new Date(ms));

// The wait end is shown the same way, with the zone named.
export const nyLabel = (ms) => `${nyTime(ms)} New York time`;

export function render({ state, task, model, session, doing, usage, lastCommit, now }) {
  const iso = new Date(now).toISOString();
  return [
    "# Autobuild status",
    "",
    `**State:** ${state}`,
    "",
    `- Doing: ${doing ?? "-"}`,
    `- Task: ${task ?? "-"}`,
    `- Model: ${model ?? "default"}`,
    `- Session: ${session ?? "-"}`,
    `- Usage: ${usage ?? "-"}`,
    `- Last commit: ${lastCommit || "-"}`,
    `- Updated: ${iso} (${nyTime(now)}, New York)`,
    "",
  ].join("\n");
}

// The text without its "Updated" line: what decides whether anything but the time changed.
export const withoutTime = (text) => String(text).replace(/^- Updated: .*$/m, "").replace(/\r\n/g, "\n");

export function makeStatus({ root, log = () => {}, push = true, now = () => Date.now() }) {
  const file = join(root, STATUS_PATH);
  const git = (...args) => spawnSync("git", args, { cwd: root, encoding: "utf8", timeout: GIT_TIMEOUT_MS });

  function write(fields) {
    try {
      const last = git("log", "-1", "--format=%s", "--invert-grep", "--grep=^status: ").stdout?.trim() ?? "";
      const text = render({ ...fields, lastCommit: last, now: now() });
      const current = existsSync(file) ? readFileSync(file, "utf8") : null;
      if (current !== null && withoutTime(current) === withoutTime(text)) return false; // only the time would change
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, text);
      const add = git("add", "--", STATUS_PATH);
      if (add.status !== 0) throw new Error(`git add: ${(add.stderr || add.error?.message || "").trim().slice(0, 150)}`);
      const subject = `status: ${fields.state}`.replace(/\s+/g, " ").slice(0, 120);
      const commit = git("commit", "-q", "--only", "-m", subject, "--", STATUS_PATH);
      if (commit.status !== 0) throw new Error(`git commit: ${(commit.stderr || commit.stdout || commit.error?.message || "").trim().slice(0, 150)}`);
      if (push) {
        const p = git("push", "-q", "-u", "origin", "HEAD");
        if (p.status !== 0) throw new Error(`git push: ${(p.stderr || p.error?.message || "").trim().slice(0, 150)}`);
      }
      return true;
    } catch (e) {
      try { log(`status: not saved (${String(e?.message ?? e).replace(/\s+/g, " ").slice(0, 200)}); carrying on`); } catch { /* never throw */ }
      return false;
    }
  }
  return { write };
}
