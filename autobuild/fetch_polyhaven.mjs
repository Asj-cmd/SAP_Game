// Downloads one Poly Haven model (CC0) into the gitignored autobuild/Incoming/,
// checking every file's md5 against Poly Haven's own file list. Step 1 of the
// asset import pipeline (godot/art/README.md); step 2 is autobuild/import_asset.mjs.
//
//   node autobuild/fetch_polyhaven.mjs <slug> [--res=1k] [--format=gltf|fbx]
//
// <slug> is the name in the asset's URL: polyhaven.com/a/<slug>. Everything on
// Poly Haven is CC0 (polyhaven.com/license), but the ASSETS.md row is still
// required before anything derived from it lands in godot/.
import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync, existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : dflt;
};
const slug = args.find((a) => !a.startsWith("--"));
if (!slug) {
  console.error("usage: node autobuild/fetch_polyhaven.mjs <slug> [--res=1k] [--format=gltf|fbx]");
  process.exit(2);
}
const res = opt("res", "1k");
const format = opt("format", "gltf");

const listing = await (await fetch(`https://api.polyhaven.com/files/${slug}`)).json();
const entry = listing?.[format]?.[res]?.[format];
if (!entry) {
  console.error(`no ${format} at ${res} for ${slug}; formats: ${Object.keys(listing ?? {}).join(", ")}`);
  process.exit(1);
}
const outDir = join("autobuild", "Incoming", "polyhaven", slug, format);
const files = [[`${slug}_${res}.${format}`, entry], ...Object.entries(entry.include ?? {})];
for (const [rel, file] of files) {
  const dest = join(outDir, rel);
  if (existsSync(dest) && md5(readFileSync(dest)) === file.md5) {
    console.log(`have  ${dest}`);
    continue;
  }
  const body = Buffer.from(await (await fetch(file.url)).arrayBuffer());
  if (md5(body) !== file.md5) {
    console.error(`md5 mismatch: ${file.url}`);
    process.exit(1);
  }
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, body);
  console.log(`got   ${dest} (${body.length} bytes)`);
}
console.log(`source: https://polyhaven.com/a/${slug} (CC0)`);
console.log(`main:   ${join(outDir, `${slug}_${res}.${format}`)}`);

function md5(buf) {
  return createHash("md5").update(buf).digest("hex");
}
