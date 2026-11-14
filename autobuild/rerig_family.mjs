#!/usr/bin/env node
// P2-1b: re-runs `tools/rerig_character.gd` for the two picked low-poly bodies
// (Quaternius "Animated low poly men/women", extracted under
// autobuild/Incoming/x/ by unzip_pack.mjs) onto the figure skeletons.
//
//   node autobuild/rerig_family.mjs [--only=male|female]
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const X = join(ROOT, "autobuild", "Incoming", "x");
const BODIES = {
  male: { src: join(X, "Animated low poly men", "FBX", "Male_LongSleeve.fbx"), rig: "figure_male", out: "figure_lp_male" },
  female: { src: join(X, "Animated low poly women", "FBX", "Female_Casual.fbx"), rig: "figure_female", out: "figure_lp_female" },
};
const only = process.argv.find((a) => a.startsWith("--only="))?.slice(7);
let failed = 0;
for (const [name, b] of Object.entries(BODIES)) {
  if (only && only !== name) continue;
  const r = spawnSync(process.execPath, [join(ROOT, "autobuild", "run_tool.mjs"), "rerig_character", "--",
    `--src=${b.src.replace(/\\/g, "/")}`, `--rig=res://art/characters/${b.rig}.gltf`,
    `--out=res://art/characters/${b.out}.gltf`], { cwd: ROOT, encoding: "utf8", timeout: 300000, maxBuffer: 1 << 26 });
  const lines = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.split("\n").filter((l) => /wrote|egg:|dropped|ERROR|error/i.test(l));
  console.log(`== ${name} (exit ${r.status})\n${lines.join("\n")}`);
  if (r.status !== 0) failed++;
}
process.exit(failed ? 1 : 0);
