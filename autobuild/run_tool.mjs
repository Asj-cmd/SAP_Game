// Runs one Godot tool script headless and prints the tail of its output,
// without the engine's exit-time leak warnings.
//   node autobuild/run_tool.mjs <tool name> [-- tool args...] [--tail=N]
import { spawnSync } from "node:child_process";

const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const args = process.argv.slice(2);
const tailArg = args.find((a) => a.startsWith("--tail="));
const tail = tailArg ? Number(tailArg.slice(7)) : 40;
const rest = args.filter((a) => a !== tailArg);
const [tool, ...toolArgs] = rest;
if (!tool) {
  console.error("usage: node autobuild/run_tool.mjs <tool> [tool args]");
  process.exit(2);
}
const r = spawnSync(
  GODOT,
  ["--headless", "--path", "godot", "--script", `res://tools/${tool}.gd`, "--", ...toolArgs],
  { encoding: "utf8", maxBuffer: 1 << 28, timeout: 900000 },
);
const noise = /Leaked instance|utilities\.cpp|ObjectDB instances|object\.cpp|resource\.cpp|still in use at exit/;
const lines = `${r.stdout ?? ""}${r.stderr ?? ""}`.split("\n").filter((l) => !noise.test(l));
console.log(lines.slice(-tail).join("\n"));
console.log(`exit ${r.status}`);
process.exit(r.status ?? 1);
