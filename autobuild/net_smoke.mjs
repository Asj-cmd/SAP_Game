// Two-process network smoke: a headless host and a headless guest of the real
// game scene on this machine (ENet, localhost), compared tick by tick.
//
//   node autobuild/net_smoke.mjs [--ticks=1800] [--team-size=3] [--speed=1] [--json]
//   node autobuild/net_smoke.mjs --ticks=20000 --speed=3   # a whole match (ends at MATCH_END)
//   add --digests --keep to write every tick's full digest and keep the files
//
// verify.mjs runs the default: 60 s of a 3v3 at real time (~70 s wall clock).
//
// The host starts first and prints "NETSMOKE host listening"; then the guest
// joins with no code (= this machine). Each writes the hash of the world it
// treats as true on every tick it saw (godot/game/debug/net_smoke.gd). Passes
// when the guest was seated, its walking moved its body in the HOST's world,
// both ended cleanly, and every tick both hashed agrees.
import { spawn } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const argv = process.argv.slice(2);
const opt = (name, fallback) => {
  const hit = argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const ticks = Number(opt("ticks", "1800"));
const teamSize = Number(opt("team-size", "3"));
const LISTEN_TIMEOUT_MS = 60000;
const RUN_TIMEOUT_MS = 600000;

const outDir = mkdtempSync(join(tmpdir(), "cashgrab-netsmoke-"));
const common = ["--headless", "--path", "godot", "--", `--net-smoke=${outDir.replaceAll("\\", "/")}`,
  `--net-smoke-ticks=${ticks}`, `--team-size=${teamSize}`,
  `--net-smoke-speed=${opt("speed", "1")}`,
  ...(argv.includes("--digests") ? ["--net-smoke-digests"] : [])];

function run(role, extra, onLine) {
  const child = spawn(GODOT, [...common, ...extra], { stdio: ["ignore", "pipe", "pipe"] });
  const result = { role, log: [], end: null, code: null };
  let buffer = "";
  const take = (chunk) => {
    buffer += chunk.toString();
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop();
    for (const line of lines) {
      result.log.push(line);
      if (line.startsWith("NETSMOKE end ")) result.end = JSON.parse(line.slice(13));
      onLine?.(line);
    }
  };
  child.stdout.on("data", take);
  child.stderr.on("data", take);
  result.done = new Promise((resolve) => child.on("close", (code) => { result.code = code; resolve(); }));
  result.kill = () => child.kill();
  return result;
}

function readHashes(role) {
  const map = new Map();
  try {
    for (const line of readFileSync(join(outDir, `${role}.txt`), "utf8").split("\n")) {
      const [tick, hash] = line.trim().split(" ");
      if (tick) map.set(Number(tick), hash);
    }
  } catch { /* missing file is reported as zero ticks */ }
  return map;
}

let listening;
const heard = new Promise((resolve) => { listening = resolve; });
const host = run("host", ["--host"], (line) => { if (line.startsWith("NETSMOKE host listening")) listening(); });
const failures = [];
const timer = setTimeout(() => { failures.push("timed out"); host.kill(); guest?.kill(); }, RUN_TIMEOUT_MS);
let guest = null;
const listenTimer = setTimeout(() => listening("timeout"), LISTEN_TIMEOUT_MS);
if ((await heard) === "timeout") failures.push("host never started listening");
clearTimeout(listenTimer);
if (!failures.length) {
  guest = run("guest", ["--join"]);
  await guest.done;
}
await Promise.race([host.done, new Promise((r) => setTimeout(r, guest ? 120000 : 0))]);
if (host.code === null) { host.kill(); await host.done; }
clearTimeout(timer);

const h = readHashes("host");
const g = readHashes("guest");
let compared = 0;
let firstMismatch = -1;
// Mismatching ticks as runs, so "from 1200 on" and "now and then" read differently.
const mismatchRuns = [];
for (const tick of [...g.keys()].sort((a, b) => a - b)) {
  if (!h.has(tick)) continue;
  compared += 1;
  if (h.get(tick) === g.get(tick)) continue;
  if (firstMismatch < 0) firstMismatch = tick;
  const last = mismatchRuns.at(-1);
  if (last && tick - last[1] <= 5) last[1] = tick;
  else mismatchRuns.push([tick, tick]);
}

if (!host.end?.ok) failures.push(`host: ${host.end?.problem || `no end line, exit ${host.code}`}`);
if (!guest?.end?.ok) failures.push(`guest: ${guest?.end?.problem || `no end line, exit ${guest?.code}`}`);
if (host.end && host.end.guest_moved <= 0) failures.push("guest's input never moved its body on the host");
if (firstMismatch >= 0) failures.push(`worlds differ from tick ${firstMismatch}`);
// Half the ticks the guest was seated for (a frame can step several ticks, so
// not every tick is seen by both ends).
const minCommon = Math.floor(((guest?.end?.last_tick ?? ticks) - (guest?.end?.joined_tick ?? 0)) / 2);
if (compared < minCommon) failures.push(`only ${compared} ticks compared (need ${minCommon})`);

const report = {
  ok: failures.length === 0, team_size: teamSize, ticks,
  compared, first_mismatch: firstMismatch,
  mismatch_runs: mismatchRuns.slice(0, 10).map(([a, b]) => (a === b ? `${a}` : `${a}-${b}`)).join(", "),
  guest_seated_tick: guest?.end?.joined_tick ?? -1, guest_seated_ms: guest?.end?.seated_ms ?? -1,
  guest_moved: host.end?.guest_moved ?? 0, humans: host.end?.humans ?? 0, bots: host.end?.bots ?? 0,
  phase: host.end?.phase ?? "", round: host.end?.round ?? 0,
  host_last_tick: host.end?.last_tick ?? -1, guest_last_tick: guest?.end?.last_tick ?? -1,
  winner: host.end?.winner ?? "", round_wins: host.end?.round_wins ?? {}, guest_team: host.end?.guest_team ?? "",
  failures,
};
if (argv.includes("--json")) {
  console.log(JSON.stringify(report));
} else {
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) {
    for (const r of [host, guest].filter(Boolean)) {
      console.log(`--- ${r.role} (exit ${r.code}), last lines ---`);
      console.log(r.log.filter((l) => l.trim()).slice(-15).join("\n"));
    }
  }
}
if (argv.includes("--keep")) console.log(`hash files kept in ${outDir}`);
else rmSync(outDir, { recursive: true, force: true });
process.exit(report.ok ? 0 : 1);
