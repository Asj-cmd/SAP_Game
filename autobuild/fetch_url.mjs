// Downloads one URL to a file and prints status, size and sha256 (PT2-4: music and CC0 proof pages).
//   node autobuild/fetch_url.mjs <url> <out path>
// Uses a generic browser User-Agent; sends nothing else about the machine or user.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

const [url, out] = process.argv.slice(2);
if (!url || !out) {
  console.error('usage: node autobuild/fetch_url.mjs <url> <out path>');
  process.exit(2);
}
const res = await fetch(url, { headers: { 'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' }, redirect: 'follow' });
const buf = Buffer.from(await res.arrayBuffer());
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, buf);
const sha = crypto.createHash('sha256').update(buf).digest('hex');
console.log(`${res.status} ${buf.length} B sha256 ${sha} -> ${out} (${res.url})`);
process.exitCode = res.ok ? 0 : 1; // not process.exit: it trips a libuv assert with fetch handles open
