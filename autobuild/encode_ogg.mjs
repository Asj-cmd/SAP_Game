// Encodes raw f32le interleaved stereo 44.1 kHz PCM (from godot/tools/decode_audio.gd) to Ogg Vorbis
// with the wasm-media-encoders package (libvorbis in WASM; there is no ffmpeg on this machine).
//   node autobuild/encode_ogg.mjs <in.f32> <out.ogg> [--quality=5] [--fade-ms=10]
// The package is installed outside the repo, by default in C:/Users/Jampa/cg_tools/oggenc
// (npm install --prefix <dir> wasm-media-encoders@0.7.0); set OGGENC_DIR to use another folder.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const opt = (name, def) => {
  const a = args.find((x) => x.startsWith(`--${name}=`));
  return a ? Number(a.split('=')[1]) : def;
};
const [input, output] = args.filter((a) => !a.startsWith('--'));
if (!input || !output) {
  console.error('usage: node autobuild/encode_ogg.mjs <in.f32> <out.ogg> [--quality=5] [--fade-ms=10]');
  process.exit(2);
}
const dir = process.env.OGGENC_DIR || 'C:/Users/Jampa/cg_tools/oggenc';
const mod = await import(pathToFileURL(path.join(dir, 'node_modules/wasm-media-encoders/dist/es/index.mjs')).href)
  .catch(() => import(pathToFileURL(path.join(dir, 'node_modules/wasm-media-encoders/dist/umd/index.js')).href));
const { createOggEncoder } = mod.default ?? mod;

const raw = fs.readFileSync(input);
const pcm = new Float32Array(raw.buffer, raw.byteOffset, raw.length / 4);
const frames = pcm.length / 2;
const left = new Float32Array(frames);
const right = new Float32Array(frames);
for (let i = 0; i < frames; i++) {
  left[i] = pcm[2 * i];
  right[i] = pcm[2 * i + 1];
}
// A short fade at both ends so a trimmed clip never clicks.
const fade = Math.min(Math.floor((opt('fade-ms', 10) / 1000) * 44100), Math.floor(frames / 2));
for (let i = 0; i < fade; i++) {
  const g = i / fade;
  left[i] *= g; right[i] *= g;
  left[frames - 1 - i] *= g; right[frames - 1 - i] *= g;
}
const encoder = await createOggEncoder();
encoder.configure({ channels: 2, sampleRate: 44100, vbrQuality: opt('quality', 5) });
const parts = [];
const BLOCK = 4096;
for (let i = 0; i < frames; i += BLOCK) {
  parts.push(Buffer.from(encoder.encode([left.subarray(i, i + BLOCK), right.subarray(i, i + BLOCK)])));
}
parts.push(Buffer.from(encoder.finalize()));
const out = Buffer.concat(parts);
fs.mkdirSync(path.dirname(output), { recursive: true });
fs.writeFileSync(output, out);
console.log(`encoded ${(frames / 44100).toFixed(3)} s -> ${output} (${out.length} B)`);
