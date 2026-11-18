// Prints duration, sample rate and channels of Ogg Vorbis files, without ffprobe.
// node autobuild/ogg_info.mjs <file-or-dir> [...]
// Duration = last page's granule position / sample rate (from the identification header).
import fs from 'node:fs';
import path from 'node:path';

function info(file) {
  const b = fs.readFileSync(file);
  const id = b.indexOf(Buffer.from([0x01, 0x76, 0x6f, 0x72, 0x62, 0x69, 0x73])); // \x01vorbis
  if (id < 0) return null;
  const channels = b[id + 11];
  const rate = b.readUInt32LE(id + 12);
  const last = b.lastIndexOf(Buffer.from('OggS'));
  const granule = Number(b.readBigUInt64LE(last + 6));
  return { channels, rate, seconds: granule / rate, bytes: b.length };
}

const files = [];
for (const arg of process.argv.slice(2)) {
  if (fs.statSync(arg).isDirectory()) {
    for (const f of fs.readdirSync(arg).sort()) if (f.endsWith('.ogg')) files.push(path.join(arg, f));
  } else files.push(arg);
}
for (const f of files) {
  const i = info(f);
  console.log(i ? `${path.basename(f)}\t${i.seconds.toFixed(2)} s\t${i.rate} Hz\t${i.channels} ch\t${i.bytes} B` : `${f}\tnot vorbis`);
}
