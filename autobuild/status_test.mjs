// Tests for status.mjs (the loop's STATUS.md heartbeat). No Claude call, no loop: it builds a throwaway git
// repo with a local "remote" in the temp folder.   node autobuild/status_test.mjs
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { makeStatus, nyLabel, nyTime, render, withoutTime, STATUS_PATH } from "./status.mjs";

let bad = 0;
const check = (ok, line) => { if (!ok) bad++; console.log(`${ok ? "ok " : "BAD"}  ${line}`); };
const run = (cwd, ...a) => spawnSync("git", a, { cwd, encoding: "utf8" });
const out = (cwd, ...a) => (run(cwd, ...a).stdout ?? "").trim();

console.log("== The file text ==");
const t1 = Date.parse("2026-11-19T05:41:30Z"); // 00:41 in New York (EST)
const t2 = Date.parse("2026-07-04T16:05:00Z"); // 12:05 PM in New York (EDT)
check(nyTime(t1).includes("12:41 AM"), `winter time in New York: ${nyTime(t1)}`);
check(nyTime(t2).includes("12:05 PM"), `summer time in New York: ${nyTime(t2)}`);
const examples = [
  ["running", { task: "PT4-8", model: "opus", session: 11, doing: "worker session" }],
  [`waiting for limit until ${nyLabel(t2)}`, { task: "PT4-8", model: "opus", session: 11, doing: "waiting after session 11 hit a usage limit" }],
  ["stopped: STOP file", { task: null, model: null, session: null, doing: "loop ended" }],
  ["stopped: No open tasks left", { doing: "loop ended" }],
];
for (const [state, f] of examples) {
  const text = render({ state, ...f, lastCommit: "PT4-8 (part): bots go for thieves", now: t1 });
  const ok = text.includes(`**State:** ${state}`) && /- Task: /.test(text) && /- Model: /.test(text) && /- Session: /.test(text) &&
    /- Last commit: PT4-8 \(part\)/.test(text) && text.includes("2026-11-19T05:41:30.000Z") && text.includes("New York");
  check(ok, `renders: ${state}`);
  if (state === "running") console.log(text.split("\n").map((l) => `        | ${l}`).join("\n"));
}
check(withoutTime(render({ state: "running", now: t1 })) === withoutTime(render({ state: "running", now: t2 })), "two texts that differ only in the time compare equal");
check(withoutTime(render({ state: "running", now: t1 })) !== withoutTime(render({ state: "stopped: x", now: t1 })), "a different state compares different");

console.log("\n== In a throwaway repo ==");
const dir = mkdtempSync(join(tmpdir(), "status-test-"));
const remote = join(dir, "remote.git"), work = join(dir, "work");
run(dir, "init", "-q", "--bare", remote);
run(dir, "init", "-q", "-b", "main", work);
for (const [k, v] of [["user.name", "t"], ["user.email", "t@example.com"], ["commit.gpgsign", "false"]]) run(work, "config", k, v);
run(work, "remote", "add", "origin", remote);
writeFileSync(join(work, "game.txt"), "game v1\n");
run(work, "add", "game.txt"); run(work, "commit", "-q", "-m", "PT4-8 (part): game work");
run(work, "push", "-q", "-u", "origin", "HEAD");
const logs = [];
let clock = t1;
const st = makeStatus({ root: work, log: (m) => logs.push(m), now: () => clock });
const subjects = () => out(work, "log", "--format=%s").split("\n");
const filesOf = (rev) => out(work, "show", "--name-only", "--format=", rev).split("\n").filter(Boolean);

// other work is STAGED and must not ride along
writeFileSync(join(work, "game.txt"), "game v2 (half done)\n");
run(work, "add", "game.txt");
check(st.write({ state: "running", task: "PT4-8", model: "opus", session: 1, doing: "worker session" }) === true, "first write returns true");
check(subjects()[0] === "status: running", `commit subject: "${subjects()[0]}"`);
check(filesOf("HEAD").join() === STATUS_PATH, `the commit holds only ${filesOf("HEAD").join()}`);
check(out(work, "diff", "--cached", "--name-only") === "game.txt", "the other staged file is still staged, not committed");
check(out(work, "rev-parse", "HEAD") === out(remote, "rev-parse", "main"), "pushed: the remote has the status commit");
check(/Last commit: PT4-8 \(part\): game work/.test(readFileSync(join(work, STATUS_PATH), "utf8")), "last commit shown is the game commit");
run(work, "reset", "-q", "game.txt"); run(work, "checkout", "--", "game.txt");

const n0 = subjects().length;
clock += 5 * 60_000; // five minutes later, same state: only the time differs
check(st.write({ state: "running", task: "PT4-8", model: "opus", session: 1, doing: "worker session" }) === false, "same state, later time: nothing written");
check(subjects().length === n0, "no new commit when only the time would change");
check(out(work, "status", "--short") === "", "the working tree stays clean");

clock += 60_000;
check(st.write({ state: `waiting for limit until ${nyLabel(t2)}`, task: "PT4-8", model: "opus", session: 1, doing: "waiting after session 1 hit a usage limit" }) === true, "a new state is written");
check(subjects()[0].startsWith("status: waiting for limit until "), `commit subject: "${subjects()[0]}"`);
check(filesOf("HEAD").join() === STATUS_PATH, "that commit also holds only STATUS.md");
check(out(work, "rev-parse", "HEAD") === out(remote, "rev-parse", "main"), "and it is pushed");
check(out(work, "status", "--short") === "", "tree clean");

st.write({ state: "stopped: STOP file", doing: "loop ended" });
const text = readFileSync(join(work, STATUS_PATH), "utf8");
check(text.includes("**State:** stopped: STOP file") && /Last commit: PT4-8 \(part\): game work/.test(text), "stopped state; last commit still skips the status commits");
check(subjects().filter((s) => s.startsWith("status: ")).length === 3, "three status commits in all, one per state change");

console.log("\n== Failures never stop the loop ==");
run(work, "remote", "set-url", "origin", join(dir, "no-such-remote.git"));
const before = logs.length;
const t0 = Date.now();
let threw = false, r;
try { r = st.write({ state: "running", task: "PT4-9", model: "opus", session: 2, doing: "worker session" }); } catch { threw = true; }
check(!threw, "a push to a missing remote does not throw");
check(logs.length === before + 1 && /^status: not saved/.test(logs.at(-1)), `exactly one log line: ${logs.at(-1)}`);
check(Date.now() - t0 < 10_000, `and it came back quickly (${Date.now() - t0} ms)`);
check(subjects()[0] === "status: running", "the commit itself was made locally and a later push will carry it");

const lone = mkdtempSync(join(tmpdir(), "status-nogit-"));
const logs2 = [];
const st2 = makeStatus({ root: lone, log: (m) => logs2.push(m) });
threw = false;
try { st2.write({ state: "running" }); } catch { threw = true; }
check(!threw && logs2.length === 1, `outside a git repo: no throw, one log line (${logs2[0] ?? ""})`);
const st3 = makeStatus({ root: join(lone, "does", "not", "exist"), log: () => { throw new Error("log itself broken"); } });
threw = false;
try { st3.write({ state: "running" }); } catch { threw = true; }
check(!threw, "even a broken log function cannot make write() throw");

console.log(bad ? `\n${bad} WRONG` : "\nall as expected");
process.exit(bad ? 1 : 0);
