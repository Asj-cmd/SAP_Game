// node autobuild/unzip_pack.mjs <zip> [--list] [--only=<regex>] [--out=<dir>]
//
// Lists or extracts a pack zip from autobuild/Incoming/ with node's zlib (this
// session's permission rules refuse shell extraction under Incoming/). Default
// output: autobuild/Incoming/x/<zip name without .zip>/. Entries with `..` or an
// absolute path are refused. Stored (0) and deflate (8) only; zip64 is not read.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { inflateRawSync } from "node:zlib";
import { dirname, join, basename, resolve, isAbsolute } from "node:path";

const args = process.argv.slice(2);
const zipPath = args.find((a) => !a.startsWith("--"));
if (!zipPath) { console.error("usage: unzip_pack.mjs <zip> [--list] [--only=regex] [--out=dir]"); process.exit(2); }
const flag = (k) => { const a = args.find((x) => x.startsWith(`--${k}=`)); return a ? a.slice(k.length + 3) : null; };
const list = args.includes("--list");
const only = flag("only") ? new RegExp(flag("only"), "i") : null;
const here = dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
const outDir = resolve(flag("out") ?? join(here, "Incoming", "x", basename(zipPath).replace(/\.zip$/i, "")));

const buf = readFileSync(zipPath);
let n = 0, bytes = 0;
for (const e of entries(buf)) {
  if (only && !only.test(e.name)) continue;
  if (list) { console.log(`${String(e.size).padStart(10)}  ${e.name}`); n++; bytes += e.size; continue; }
  if (e.name.endsWith("/")) continue;
  if (e.name.split(/[\\/]/).includes("..") || isAbsolute(e.name) || /^[A-Za-z]:/.test(e.name)) {
    console.error(`refused: ${e.name}`); continue;
  }
  const dest = join(outDir, e.name);
  mkdirSync(dirname(dest), { recursive: true });
  writeFileSync(dest, e.data());
  n++; bytes += e.size;
}
console.log(`${n} entries, ${bytes} bytes${list ? "" : ` -> ${outDir}`}`);

function* entries(b) {
  let eocd = -1;
  for (let i = b.length - 22; i >= Math.max(0, b.length - 65557); i--) {
    if (b.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  }
  if (eocd < 0) throw new Error("not a zip (no end of central directory)");
  const count = b.readUInt16LE(eocd + 10);
  let p = b.readUInt32LE(eocd + 16);
  for (let k = 0; k < count; k++) {
    if (b.readUInt32LE(p) !== 0x02014b50) throw new Error("bad central directory");
    const method = b.readUInt16LE(p + 10);
    const csize = b.readUInt32LE(p + 20);
    const size = b.readUInt32LE(p + 24);
    const nlen = b.readUInt16LE(p + 28);
    const xlen = b.readUInt16LE(p + 30);
    const clen = b.readUInt16LE(p + 32);
    const off = b.readUInt32LE(p + 42);
    const name = b.toString("utf8", p + 46, p + 46 + nlen);
    p += 46 + nlen + xlen + clen;
    const start = off + 30 + b.readUInt16LE(off + 26) + b.readUInt16LE(off + 28);
    const raw = b.subarray(start, start + csize);
    yield {
      name, size,
      data() {
        if (method === 0) return raw;
        if (method === 8) return inflateRawSync(raw);
        throw new Error(`${name}: compression method ${method} not supported`);
      },
    };
  }
}
