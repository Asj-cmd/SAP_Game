#!/usr/bin/env node
// P2-1b: re-runs `tools/rerig_character.gd` for the two picked low-poly bodies
// (Quaternius "Animated low poly men/women", extracted under
// autobuild/Incoming/x/ by unzip_pack.mjs) onto the figure skeletons.
//
//   node autobuild/rerig_family.mjs [--only=male,dress,...]
import { spawnSync } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const X = join(ROOT, "autobuild", "Incoming", "x");
const MEN = join(X, "Animated low poly men", "FBX");
const WOMEN = join(X, "Animated low poly women", "FBX");
// One body per family member (D3, 2026-11-14), each a different outfit from the
// two packs. "male" is dad's; "female" is the first woman picked, kept as a spare.
// P2-6: each family body also gets its hair (and dad his belly) through `args`:
// dad (shirt) a comb-over, mom (dress) a tall stiff hairdo, the boys (male,
// casual) a mohawk, the girls (alt, tank) two pigtails. PT2-8: bigger mohawks
// (16 / 13 cm), a 34 cm beehive, uneven pigtails.
const BODIES = {
  male: { src: join(MEN, "Male_LongSleeve.fbx"), rig: "figure_male", out: "figure_lp_male",
    args: ["--hair=mohawk", "--hair-height=16"] },
  female: { src: join(WOMEN, "Female_Casual.fbx"), rig: "figure_female", out: "figure_lp_female" },
  dress: { src: join(WOMEN, "Female_Dress.fbx"), rig: "figure_female", out: "figure_lp_dress",
    // Her bun makes the head box 1.77 deep for 1 wide; the other women are 1.27.
    args: ["--egg-depth-max=1.27", "--hair=beehive"] },
  alt: { src: join(WOMEN, "Female_Alternative.fbx"), rig: "figure_female", out: "figure_lp_alt",
    args: ["--hair=pigtails_long"] },
  tank: { src: join(WOMEN, "Female_TankTop.fbx"), rig: "figure_female", out: "figure_lp_tank",
    args: ["--hair=pigtails_short"] },
  shirt: { src: join(MEN, "Male_Shirt.fbx"), rig: "figure_male", out: "figure_lp_shirt",
    args: ["--hair=combover", "--belly=13"] },
  casual: { src: join(MEN, "Male_Casual.fbx"), rig: "figure_male", out: "figure_lp_casual",
    // PT4-8 REDO: a narrow ridge (half the elder boy's base width); 0.32 read as a dome.
    args: ["--hair=mohawk", "--hair-height=13", "--hair-width=0.16"] },
};
const only = process.argv.find((a) => a.startsWith("--only="))?.slice(7);
let failed = 0;
for (const [name, b] of Object.entries(BODIES)) {
  if (only && !only.split(",").includes(name)) continue;
  const r = spawnSync(process.execPath, [join(ROOT, "autobuild", "run_tool.mjs"), "rerig_character", "--",
    `--src=${b.src.replace(/\\/g, "/")}`, `--rig=res://art/characters/${b.rig}.gltf`,
    `--out=res://art/characters/${b.out}.gltf`, ...(b.kinds ? [`--kinds=${b.kinds}`] : []), ...(b.args ?? [])], { cwd: ROOT, encoding: "utf8", timeout: 300000, maxBuffer: 1 << 26 });
  const lines = `${r.stdout ?? ""}\n${r.stderr ?? ""}`.split("\n").filter((l) => /wrote|egg:|hair:|mohawk:|pigtail|belly:|facing:|axes:|dropped|ERROR|error/i.test(l));
  console.log(`== ${name} (exit ${r.status})\n${lines.join("\n")}`);
  if (r.status !== 0) failed++;
}
process.exit(failed ? 1 : 0);
