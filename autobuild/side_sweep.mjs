#!/usr/bin/env node
// Side-bias sweep (P0-5b): bot_match --once over seeds x team sizes, each seed
// played as-is and with --swap-houses, and a tally of wins by TEAM NAME and by
// HOUSE. House B is House A turned half a circle, so on a fair level neither
// count should lean.
//
//   node autobuild/side_sweep.mjs [--sizes=2,3,4] [--seeds=8] [--first-seed=1] [--jobs=3]
//
// A measuring tool, not a gate: a sweep is minutes of wall clock.
import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const GODOT = process.env.GODOT_BIN || "godot";
const arg = (name, fallback) => {
  const hit = process.argv.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : fallback;
};
const sizes = arg("sizes", "2,3,4").split(",").map(Number);
const seeds = Number(arg("seeds", "8"));
const jobs = Number(arg("jobs", "3"));
const firstSeed = Number(arg("first-seed", "1"));

const runs = [];
for (const size of sizes)
  for (let seed = firstSeed; seed < firstSeed + seeds; seed++)
    for (const swapped of [false, true]) runs.push({ size, seed, swapped });

function play(run) {
  const args = ["--headless", "--path", path.join(ROOT, "godot"), "--script", "res://tools/bot_match.gd", "--",
    `--team-size=${run.size}`, `--seed=${run.seed}`, "--once"];
  if (run.swapped) args.push("--swap-houses");
  return new Promise((resolve) => {
    let out = "";
    const child = spawn(GODOT, args, { cwd: ROOT });
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", (d) => (out += d));
    child.on("close", () => {
      const winner = (out.match(/^winner\s+(\S+)/m) ?? [, "?"])[1];
      const rounds = (out.match(/^rounds won\s+(.*)$/m) ?? [, "?"])[1].trim();
      const raiding = (out.match(/^raiding\s+(.*)$/m) ?? [, "?"])[1].trim();
      if (rounds === "?") console.log(`-- ${run.size}v${run.size} seed ${run.seed} gave no result:\n${out.split("\n").slice(-25).join("\n")}`);
      resolve({ ...run, winner: winner.startsWith("team_") ? winner : "none", rounds, raiding });
    });
  });
}

const results = [];
let next = 0;
async function worker() {
  while (next < runs.length) {
    const run = runs[next++];
    const r = await play(run);
    results.push(r);
    console.log(`${r.size}v${r.size} seed ${r.seed} ${r.swapped ? "swapped" : "as-is  "}  winner ${r.winner.padEnd(7)} rounds ${r.rounds}  raiding ${r.raiding}`);
  }
}
await Promise.all(Array.from({ length: jobs }, worker));

// House A is team_a's unless swapped.
const houseOf = (r) => (r.winner === "none" ? "none" : (r.winner === "team_a") !== r.swapped ? "A" : "B");
console.log("\n== Summary ==");
let total = { team_a: 0, team_b: 0, A: 0, B: 0, none: 0, n: 0 };
for (const size of sizes) {
  const rows = results.filter((r) => r.size === size);
  const asIs = rows.filter((r) => !r.swapped);
  const count = (list, f, v) => list.filter((r) => f(r) === v).length;
  const line = (label, list) =>
    `  ${label.padEnd(8)} team_a ${count(list, (r) => r.winner, "team_a")}  team_b ${count(list, (r) => r.winner, "team_b")}  ` +
    `house A ${count(list, houseOf, "A")}  house B ${count(list, houseOf, "B")}  undecided ${count(list, (r) => r.winner, "none")}  of ${list.length}`;
  console.log(`${size}v${size}`);
  console.log(line("as-is", asIs));
  console.log(line("all", rows));
  total.team_a += count(asIs, (r) => r.winner, "team_a");
  total.team_b += count(asIs, (r) => r.winner, "team_b");
  total.A += count(rows, houseOf, "A");
  total.B += count(rows, houseOf, "B");
  total.none += count(rows, (r) => r.winner, "none");
  total.n += asIs.length;
}
console.log(`as-is over all sizes: team_a ${total.team_a}, team_b ${total.team_b} of ${total.n}`);
console.log(`by house, as-is + swapped: A ${total.A}, B ${total.B}, undecided ${total.none} of ${total.n * 2}`);
