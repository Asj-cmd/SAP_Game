// Downloads one Poly Haven texture set (CC0) straight into godot/art/textures/<slug>/,
// checking every file's md5 against Poly Haven's own file list. The house shell's
// surfaces (P3-2; STYLE.md §3.3 "The kit") are tiled from these through the
// ArtTheme's materials.
//
//   node autobuild/fetch_texture.mjs <slug> [--res=1k] [--maps=diff,rough] [--info]
//
// <slug> is the name in the asset's URL: polyhaven.com/a/<slug>. Everything on
// Poly Haven is CC0 (polyhaven.com/license); the ASSETS.md row is still required.
// --info prints the maps on offer and the real-world size (mm) and downloads nothing.
// Writes SOURCE.txt beside the maps: URL, licence, date, size, md5 of each file.
import { createHash } from "node:crypto";
import { mkdirSync, writeFileSync, existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : dflt;
};
const slugs = args.filter((a) => !a.startsWith("--"));
if (slugs.length === 0) {
  console.error("usage: node autobuild/fetch_texture.mjs <slug>... [--res=1k] [--maps=diff,rough] [--info]");
  process.exit(2);
}
const res = opt("res", "1k");
// Poly Haven's map names: Diffuse, Rough, nor_gl, AO, Displacement ...
const MAP_NAMES = { diff: "Diffuse", rough: "Rough", nor: "nor_gl", ao: "AO" };
const maps = opt("maps", "diff").split(",").filter(Boolean);

for (const slug of slugs) {
  const filesRes = await fetch(`https://api.polyhaven.com/files/${slug}`);
  if (!filesRes.ok) {
    console.log(`${slug}: not on Poly Haven (${filesRes.status})`);
    continue;
  }
  const listing = await filesRes.json();
  const info = await (await fetch(`https://api.polyhaven.com/info/${slug}`)).json();
  const dims = info?.dimensions ?? null;
  if (args.includes("--info")) {
    console.log(`${slug}: type ${info?.type} maps ${Object.keys(listing).join(",")} size(mm) ${JSON.stringify(dims)}`);
    continue;
  }
  // Poly Haven asset types: 0 HDRI, 1 texture, 2 model.
  if (info?.type !== 1) {
    console.error(`${slug}: not a texture (type ${info?.type})`);
    process.exit(1);
  }
  const outDir = join("godot", "art", "textures", slug);
  mkdirSync(outDir, { recursive: true });
  const lines = [
    `source: https://polyhaven.com/a/${slug}`,
    "licence: CC0 (https://polyhaven.com/license)",
    `fetched: ${new Date().toISOString().slice(0, 10)}`,
    `real size (mm): ${JSON.stringify(dims)}`,
  ];
  for (const short of maps) {
    const key = MAP_NAMES[short] ?? short;
    const file = listing?.[key]?.[res]?.jpg ?? listing?.[key]?.[res]?.png;
    if (!file) {
      console.error(`${slug}: no ${key} at ${res}`);
      process.exit(1);
    }
    const ext = file.url.endsWith(".png") ? "png" : "jpg";
    const dest = join(outDir, `${slug}_${short}_${res}.${ext}`);
    if (!(existsSync(dest) && md5(readFileSync(dest)) === file.md5)) {
      const body = Buffer.from(await (await fetch(file.url)).arrayBuffer());
      if (md5(body) !== file.md5) {
        console.error(`md5 mismatch: ${file.url}`);
        process.exit(1);
      }
      writeFileSync(dest, body);
      console.log(`got   ${dest} (${body.length} bytes)`);
    } else {
      console.log(`have  ${dest}`);
    }
    lines.push(`${short}: ${file.url} md5 ${file.md5}`);
  }
  writeFileSync(join(outDir, "SOURCE.txt"), lines.join("\n") + "\n");
}

function md5(buf) {
  return createHash("md5").update(buf).digest("hex");
}
