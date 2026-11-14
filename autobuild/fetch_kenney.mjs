// Downloads one Kenney asset pack (CC0) into the gitignored autobuild/Incoming/kenney/
// and unpacks it there. Step 1 of the asset import pipeline for Kenney packs
// (godot/art/README.md); step 2 is autobuild/import_asset.mjs on one of its .glb files.
//
//   node autobuild/fetch_kenney.mjs <slug>        e.g. furniture-kit
//   node autobuild/fetch_kenney.mjs <slug> --zip=<already downloaded .zip>
//
// <slug> is the name in the pack's URL: kenney.nl/assets/<slug>. The page is read for
// its licence line (refuses anything that is not CC0) and its download id; the zip
// comes from the site's own signed-link endpoint, as the Download button does. The
// sha256 of the zip is printed and written to <slug>/SOURCE.txt for ASSETS.md.
//
// Unzipping is done here (node's zlib) rather than by a shell: entries with absolute
// paths or ".." are refused, so a zip can only write inside its own folder.
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { inflateRawSync } from "node:zlib";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const args = process.argv.slice(2);
const opt = (name, dflt) => {
  const hit = args.find((a) => a.startsWith(`--${name}=`));
  return hit ? hit.slice(name.length + 3) : dflt;
};
const slug = args.find((a) => !a.startsWith("--"));
if (!slug || !/^[a-z0-9-]+$/.test(slug)) {
  console.error("usage: node autobuild/fetch_kenney.mjs <slug> [--zip=file.zip]");
  process.exit(2);
}
const page = `https://kenney.nl/assets/${slug}`;
const headers = { "User-Agent": "Mozilla/5.0 (compatible; asset-fetch)", Referer: page };
const outDir = join(ROOT, "autobuild", "Incoming", "kenney", slug);

let zip;
const local = opt("zip", "");
if (local) {
  zip = readFileSync(local);
} else {
  const html = await (await fetch(page, { headers })).text();
  if (!/creativecommons\.org\/publicdomain\/zero\/1\.0/.test(html)) {
    console.error(`${page}: no CC0 licence line on the page; not downloading`);
    process.exit(1);
  }
  const id = html.match(/data-download-id='([0-9a-f]+)'/)?.[1];
  if (!id) {
    console.error(`${page}: no download id on the page`);
    process.exit(1);
  }
  const link = await (await fetch(`https://kenney.nl/download-link/${id}`, { headers, cache: "no-store" })).json();
  if (!link.url) {
    console.error(`${page}: the site gave no download link`);
    process.exit(1);
  }
  zip = Buffer.from(await (await fetch(link.url, { headers })).arrayBuffer());
}
const sha = createHash("sha256").update(zip).digest("hex");
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, `${slug}.zip`), zip);

let written = 0;
for (const entry of entries(zip)) {
  if (entry.name.endsWith("/")) continue;
  const norm = entry.name.replace(/\\/g, "/");
  if (norm.startsWith("/") || /^[a-zA-Z]:/.test(norm) || norm.split("/").includes("..")) {
    console.error(`refused entry: ${entry.name}`);
    process.exit(1);
  }
  const dest = resolve(outDir, norm);
  if (!dest.startsWith(resolve(outDir) + sep)) {
    console.error(`refused entry: ${entry.name}`);
    process.exit(1);
  }
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, entry.data());
  written += 1;
}
const licence = ["License.txt", "license.txt", "LICENSE.txt"].map((f) => join(outDir, f)).find(existsSync);
const licenceText = licence ? readFileSync(licence, "utf8") : "";
writeFileSync(
  join(outDir, "SOURCE.txt"),
  `source: ${page}\nlicence: CC0 1.0 (page${licence ? " and License.txt" : ""})\nzip sha256: ${sha}\nfetched: ${new Date().toISOString().slice(0, 10)}\n`,
);
console.log(`${written} files -> ${outDir}`);
console.log(`zip sha256 ${sha} (${zip.length} bytes)`);
console.log(`licence file: ${licence ?? "none"}${/CC0|Creative Commons Zero|public domain/i.test(licenceText) ? " (says CC0)" : ""}`);

// Minimal zip reader: end-of-central-directory -> central directory -> local headers.
// Stored (0) and deflate (8) only, which is all a pack zip uses.
function* entries(buf) {
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 65557); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("not a zip (no end of central directory)");
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  for (let n = 0; n < count; n++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) throw new Error("bad central directory");
    const method = buf.readUInt16LE(p + 10);
    const csize = buf.readUInt32LE(p + 20);
    const nlen = buf.readUInt16LE(p + 28);
    const xlen = buf.readUInt16LE(p + 30);
    const clen = buf.readUInt16LE(p + 32);
    const off = buf.readUInt32LE(p + 42);
    const name = buf.toString("utf8", p + 46, p + 46 + nlen);
    p += 46 + nlen + xlen + clen;
    const lnlen = buf.readUInt16LE(off + 26);
    const lxlen = buf.readUInt16LE(off + 28);
    const start = off + 30 + lnlen + lxlen;
    const raw = buf.subarray(start, start + csize);
    yield {
      name,
      data() {
        if (method === 0) return raw;
        if (method === 8) return inflateRawSync(raw);
        throw new Error(`${name}: compression method ${method} not supported`);
      },
    };
  }
}
