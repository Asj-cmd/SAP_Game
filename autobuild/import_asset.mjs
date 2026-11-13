// The asset import pipeline, step 2 (step 1 is a download into the gitignored
// autobuild/Incoming/, e.g. autobuild/fetch_polyhaven.mjs). See godot/art/README.md.
//
//   node autobuild/import_asset.mjs <source .glb/.gltf/.fbx> --out=res://art/props/<name>.glb
//        [--units=auto|m|cm|<factor>] [--height=cm | --fit=x,y,z] [--yaw=deg]
//        [--pivot=base|centre|keep] [--role=prop|hero|cash] [--max-tris=N]
//        [--material=wood | --material=Seat:fabric,Legs:wood] [--url=... --licence=...] [--dry]
//   node autobuild/import_asset.mjs --again=godot/art/props/<name>.source.json
//   node autobuild/import_asset.mjs --all      # re-run every *.source.json under godot/art
//
// Runs godot/tools/import_asset.gd headless (scale to 1 unit = 1 cm, pivot, one
// merged mesh, no collision, budget check), then lets Godot import the new .glb
// so the game can load it, and writes <name>.source.json next to it: the exact
// source and flags, so the import can be repeated from a fresh download.
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { join, relative, resolve } from "node:path";

const GODOT = process.env.GODOT_BIN || "C:/Godot/Godot_v4.7.1-stable_win64_console.exe";
const ROOT = resolve(import.meta.dirname, "..");
const args = process.argv.slice(2);

const jobs = [];
const again = args.find((a) => a.startsWith("--again="));
if (args.includes("--all")) {
  for (const file of walk(join(ROOT, "godot", "art"))) {
    if (file.endsWith(".source.json")) jobs.push(JSON.parse(readFileSync(file, "utf8")));
  }
  if (jobs.length === 0) console.log("no *.source.json under godot/art");
} else if (again) {
  jobs.push(JSON.parse(readFileSync(resolve(again.slice(8)), "utf8")));
} else {
  const src = args.find((a) => !a.startsWith("--"));
  if (!src) {
    console.error("usage: node autobuild/import_asset.mjs <source> --out=res://art/<dir>/<name>.glb [flags]");
    process.exit(2);
  }
  jobs.push({ src: relative(ROOT, resolve(src)).replaceAll("\\", "/"), flags: args.filter((a) => a.startsWith("--")) });
}

let failures = 0;
const written = [];
for (const job of jobs) {
  const src = resolve(ROOT, job.src);
  if (!existsSync(src)) {
    console.log(`FAIL missing source ${job.src}${job.url ? ` (download it again from ${job.url})` : ""}`);
    failures++;
    continue;
  }
  const r = spawnSync(
    GODOT,
    ["--headless", "--path", join(ROOT, "godot"), "--script", "res://tools/import_asset.gd", "--", `--src=${src}`, ...job.flags],
    { encoding: "utf8", maxBuffer: 1 << 26, timeout: 300000 },
  );
  const noise = /Leaked instance|utilities\.cpp|ObjectDB instances|object\.cpp|resource\.cpp|still in use at exit|^Godot Engine v/;
  // The reader also tries to load the source's textures (FBX references .jpg/.exr
  // files outside the project). They are dropped anyway, so their errors are noise.
  // An engine message is a block: the ERROR/WARNING line plus its indented
  // "at:" / backtrace lines, and the texture hint can be on either, so each
  // block is judged whole.
  const texture = /image|Image|No loader found|png|PNG|jpe?g|exr|texture/;
  let textureErrors = 0;
  const out = [];
  let block = [];
  const flush = () => {
    if (block.length === 0) return;
    const text = block.join("\n");
    if (/^(ERROR|WARNING):/.test(block[0]) && texture.test(text)) textureErrors++;
    else if (!noise.test(block[0])) out.push(...block);
    block = [];
  };
  for (const line of `${r.stdout ?? ""}${r.stderr ?? ""}`.split("\n")) {
    if (!line.trim()) continue;
    if (/^\s/.test(line) && block.length > 0) block.push(line);
    else {
      flush();
      block = [line];
    }
  }
  flush();
  if (textureErrors) out.push(`(${textureErrors} texture-load errors from the source ignored: textures are dropped)`);
  console.log(out.join("\n"));
  if (r.status !== 0) {
    failures++;
    continue;
  }
  const outFlag = job.flags.find((f) => f.startsWith("--out="));
  if (outFlag && !job.flags.includes("--dry")) {
    const res = outFlag.slice(6);
    const sidecar = join(ROOT, "godot", res.replace("res://", "").replace(/\.glb$|\.gltf$/, ".source.json"));
    const record = { src: job.src, url: job.url ?? flagValue(args, "url") ?? "", licence: job.licence ?? flagValue(args, "licence") ?? "", flags: job.flags.filter((f) => !f.startsWith("--url=") && !f.startsWith("--licence=")) };
    writeFileSync(sidecar, `${JSON.stringify(record, null, 2)}\n`);
    written.push(res);
  }
}

if (written.length > 0) {
  // The game loads res://*.glb through the editor's importer (.import + .godot/imported).
  const imp = spawnSync(GODOT, ["--headless", "--path", join(ROOT, "godot"), "--import"], { encoding: "utf8", timeout: 600000 });
  const errors = `${imp.stdout}${imp.stderr}`.split("\n").filter((l) => /ERROR|error:/i.test(l) && /art\//.test(l));
  console.log(errors.length ? errors.join("\n") : `imported ${written.join(", ")}`);
  if (imp.status !== 0) failures++;
}
process.exit(failures ? 1 : 0);

function flagValue(list, name) {
  const hit = list.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : undefined;
}

function* walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) yield* walk(path);
    else yield path;
  }
}
