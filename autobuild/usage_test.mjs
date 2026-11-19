// Tests for usage.mjs and runner.mjs (the loop's 5-hour guard). No real Claude call, no loop.
//   node autobuild/usage_test.mjs
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { UsageTracker, readingFromEvent, eventsFromChunk, textFromStream, preflight, monitorDecision, usageResetAt, MIN } from "./usage.mjs";
import { runClaude } from "./runner.mjs";

let bad = 0;
const check = (ok, line) => { if (!ok) bad++; console.log(`${ok ? "ok " : "BAD"}  ${line}`); };
const NOW = Date.parse("2026-11-19T06:00:00Z");
const sec = (ms) => Math.floor(ms / 1000);

// the real shape, as printed by claude 2.1.322
const real = {
  type: "rate_limit_event",
  rate_limit_info: {
    status: "allowed_warning", resetsAt: 1795077600, rateLimitType: "five_hour", utilization: 0.94,
    unifiedWindows: {
      five_hour: { utilization: 0.94, resetsAt: 1795077600, status: "allowed_warning", surpassedThreshold: 0.9 },
      seven_day: { utilization: 0.83, resetsAt: 1795140000, status: "allowed_warning", surpassedThreshold: 0.75 },
    },
  },
};
const ev = (five, seven, resetsAt = sec(NOW) + 3600, status = "allowed") => ({
  type: "rate_limit_event",
  rate_limit_info: { status, resetsAt, rateLimitType: "five_hour", utilization: five,
    unifiedWindows: { five_hour: { utilization: five, resetsAt, status }, ...(seven === null ? {} : { seven_day: { utilization: seven, resetsAt: resetsAt + 86400, status: "allowed" } }) } },
});

console.log("== Reading the events ==");
let r = readingFromEvent(real);
check(r.five_hour.utilization === 0.94 && r.seven_day.utilization === 0.83 && r.five_hour.resetsAt === 1795077600, "the real event: 94 % five-hour, 83 % weekly");
check(readingFromEvent({ type: "assistant" }) === null && readingFromEvent(null) === null, "other events are ignored");
r = readingFromEvent({ type: "rate_limit_event", rate_limit_info: { rateLimitType: "five_hour", utilization: 0.4, resetsAt: 123 } });
check(r.five_hour.utilization === 0.4 && r.seven_day === null, "no unifiedWindows: the top-level window is used");
const st = {}; const evs = [...eventsFromChunk(st, '{"type":"a"}\n{"type":"b"'), ...eventsFromChunk(st, '}\nnot json\n')];
check(evs.length === 2 && evs[1].type === "b", "stdout split into JSON lines, even across chunks");

console.log("\n== The tracker ==");
const tr = new UsageTracker();
tr.update(readingFromEvent(ev(0.5, 0.2, sec(NOW) + 3600)));
check(tr.fiveHour(NOW).utilization === 0.5 && tr.summary(NOW) === "5-hour 50%, weekly 20%", `summary: ${tr.summary(NOW)}`);
check(tr.fiveHour(NOW + 2 * 3600_000) === null, "a reading is dropped once its window has reset");
tr.update(readingFromEvent(ev(0.7, null, sec(NOW) + 3600)));
check(tr.sevenDay(NOW).utilization === 0.2, "a later event without a weekly window keeps the old weekly reading");

console.log("\n== Before a session starts ==");
const p = (u, resetsAt) => { const t = new UsageTracker(); t.update(readingFromEvent(ev(u, null, resetsAt))); return preflight(t, { stopPct: 75, now: NOW }); };
check(p(0.74, sec(NOW) + 3600).wait === false, "74 %: go");
let pf = p(0.75, sec(NOW) + 3600);
check(pf.wait && pf.pct === 75 && pf.until === (sec(NOW) + 3600) * 1000 + 3 * MIN, "75 %: wait until the reset + 3 min");
check(p(0.94, sec(NOW) - 60).wait === false, "a reading from a window that already reset: go");
check(preflight(new UsageTracker(), { stopPct: 75, now: NOW }).wait === false, "no reading at all: go");

console.log("\n== While a session runs ==");
const md = (u, o = {}) => { const t = new UsageTracker(); t.update(readingFromEvent(ev(u, null))); return monitorDecision(t, { now: NOW, ...o }).action; };
check(md(0.5) === "ok" && md(0.7499) === "ok", "under 75 %: carry on");
check(md(0.75) === "wrap", "75 %: ask it to wrap up");
check(md(0.77, { wrapSince: NOW - MIN }) === "ok", "wrapping at 77 %, 1 min in: give it time");
check(md(0.80, { wrapSince: NOW - MIN }) === "kill", "wrapping, reached 80 %: cut it off");
check(md(0.76, { wrapSince: NOW - 15 * MIN }) === "kill", "wrapping, 15 min passed: cut it off");
check(md(0.76, { wrapSince: NOW - 5 * MIN, wrapMin: 5 }) === "kill", "WRAP_UP_MIN is respected");

console.log("\n== The real limit ==");
const t2 = new UsageTracker(); t2.update(readingFromEvent(ev(1.0, 0.9, sec(NOW) + 7200, "rejected")));
check(usageResetAt(t2, NOW) === (sec(NOW) + 7200) * 1000, "a full window: its exact reset");
const t3 = new UsageTracker(); t3.update(readingFromEvent(ev(0.5, null)));
check(usageResetAt(t3, NOW) === null, "nothing full: null");

console.log("\n== Text from the stream ==");
const stream = [
  JSON.stringify({ type: "system", subtype: "init" }),
  JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: "Working." }, { type: "tool_use", name: "Bash" }] } }),
  JSON.stringify({ type: "assistant", message: { content: [{ type: "text", text: "You've hit your limit · resets 3am (America/New_York)" }] } }),
  JSON.stringify({ type: "result", is_error: true, result: "You've hit your limit · resets 3am (America/New_York)" }),
].join("\n");
const txt = textFromStream(stream);
check(txt.split("\n").length === 3 && txt.includes("resets 3am"), "assistant text and the result come out as plain lines");

console.log("\n== runner.mjs with a fake claude ==");
const dir = mkdtempSync(join(tmpdir(), "usage-test-"));
const fake = join(dir, "fake.mjs");
writeFileSync(fake, `
const mode = process.argv[2];
process.stdin.resume(); process.stdin.on("data", () => {});
const out = (o) => console.log(JSON.stringify(o));
out({ type: "rate_limit_event", rate_limit_info: { rateLimitType: "five_hour", utilization: 0.3, resetsAt: 9999999999 } });
if (mode === "hang") setInterval(() => {}, 1000);
else { out({ type: "result", result: "done" }); setTimeout(() => process.exit(0), 100); }
`);
const seen = [];
let res = await runClaude({ command: "node", args: [fake, "ok"], input: "hi", cwd: dir, timeoutMs: 20_000, onEvent: (e) => seen.push(e.type) });
check(res.status === 0 && seen.join() === "rate_limit_event,result", `a normal run: exit ${res.status}, events ${seen.join()}`);
let t0 = Date.now();
res = await runClaude({ command: "node", args: [fake, "hang"], input: "hi", cwd: dir, timeoutMs: 30_000, tickMs: 200, onTick: (ms) => (ms > 1000 ? { kill: "test cut-off" } : null) });
check(res.killedFor === "test cut-off" && Date.now() - t0 < 10_000, `a session that will not end is cut off by onTick (${Date.now() - t0} ms)`);
t0 = Date.now();
res = await runClaude({ command: "node", args: [fake, "hang"], input: "hi", cwd: dir, timeoutMs: 1500, tickMs: 200 });
check(res.error?.code === "ETIMEDOUT" && Date.now() - t0 < 10_000, `a timeout is reported as ETIMEDOUT (${Date.now() - t0} ms)`);
res = await runClaude({ command: "definitely-not-a-program-xyz", args: [], input: "", cwd: dir, timeoutMs: 5000 });
check(res.status !== 0, `a program that does not exist fails cleanly (exit ${res.status})`);

console.log(bad ? `\n${bad} WRONG` : "\nall as expected");
process.exit(bad ? 1 : 0);
