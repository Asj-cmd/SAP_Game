// Builds the Windows release: build/CashGrab.exe, then smoke-runs it.
//   node autobuild/build.mjs
import { spawnSync } from "node:child_process";
import { readFileSync, statSync, existsSync, mkdirSync } from "node:fs";

const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const proj = readFileSync("godot/project.godot", "utf8");
if (/^MCP\w*=.*addons\/godot_mcp/m.test(proj)) {
  console.error("BUILD: refused. project.godot has godot_mcp autoloads (the editor plugin re-adds them). Remove them from [autoload].");
  process.exit(1);
}
const run = (args, timeout) =>
  spawnSync(GODOT, ["--headless", "--path", "godot", ...args], { encoding: "utf8", maxBuffer: 1 << 28, timeout });
mkdirSync("build", { recursive: true });
run(["--import"], 600000);
const r = run(["--export-release", "Windows Desktop", "../build/CashGrab.exe"], 600000);
console.log(`${r.stdout ?? ""}${r.stderr ?? ""}`.split("\n").slice(-15).join("\n"));
if (!existsSync("build/CashGrab.exe")) { console.error("BUILD: failed, no exe"); process.exit(1); }
const mb = (statSync("build/CashGrab.exe").size / 1048576).toFixed(1);
const s = spawnSync("build/CashGrab.exe", ["--headless", "--quit-after", "900", "--", "--solo"],
  { encoding: "utf8", maxBuffer: 1 << 28, timeout: 120000 });
const out = `${s.stdout ?? ""}${s.stderr ?? ""}`;
const bad = out.split("\n").filter((l) => /SCRIPT ERROR|Parse Error|Failed to load/.test(l));
if (bad.length) { console.error("BUILD: smoke run errors:\n" + bad.slice(0, 10).join("\n")); process.exit(1); }
console.log(`BUILD: ok ${mb} MB`);
