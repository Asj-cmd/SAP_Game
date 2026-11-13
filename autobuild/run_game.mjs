// Runs the game windowed with the given user args and prints the tail of its
// output, without the engine's exit-time leak warnings. For captures:
//   node autobuild/run_game.mjs [--tail=N] [--timeout=s] [--headless] -- --capture-follow=team_b:0,12,0.5 --capture-path=...
import { spawnSync } from "node:child_process";

const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const args = process.argv.slice(2);
const split = args.indexOf("--");
const own = split < 0 ? args : args.slice(0, split);
const gameArgs = split < 0 ? [] : args.slice(split + 1);
const tailArg = own.find((a) => a.startsWith("--tail="));
const tail = tailArg ? Number(tailArg.slice(7)) : 60;
const timeoutArg = own.find((a) => a.startsWith("--timeout="));
const seconds = timeoutArg ? Number(timeoutArg.slice(10)) : 600;
const headless = own.includes("--headless") ? ["--headless"] : [];
const r = spawnSync(GODOT, [...headless, "--path", "godot", "--", ...gameArgs],
  { encoding: "utf8", maxBuffer: 1 << 28, timeout: seconds * 1000, killSignal: "SIGKILL" });
if (r.error) console.log(`run_game: ${r.error.message}`);
const noise = /Leaked instance|utilities\.cpp|ObjectDB instances|object\.cpp|resource\.cpp|still in use at exit|^\s*$/;
const lines = `${r.stdout ?? ""}${r.stderr ?? ""}`.split("\n").filter((l) => !noise.test(l));
console.log(lines.slice(-tail).join("\n"));
console.log(`exit ${r.status}`);
process.exit(r.status ?? 1);
