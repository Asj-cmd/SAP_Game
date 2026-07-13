// Quick structural smoke-check of a .glb file: parses the binary GLB header
// and JSON chunk directly (no Three.js/browser needed) to confirm mesh,
// skin/joints, and animation clips are present.
import fs from "fs";

const path = process.argv[2];
const buf = fs.readFileSync(path);

const magic = buf.readUInt32LE(0);
if (magic !== 0x46546c67) throw new Error("Not a glTF binary (bad magic)");
const version = buf.readUInt32LE(4);
const length = buf.readUInt32LE(8);

let offset = 12;
let json = null;
while (offset < length) {
  const chunkLength = buf.readUInt32LE(offset);
  const chunkType = buf.readUInt32LE(offset + 4);
  const chunkData = buf.subarray(offset + 8, offset + 8 + chunkLength);
  if (chunkType === 0x4e4f534a) json = JSON.parse(chunkData.toString("utf8"));
  offset += 8 + chunkLength;
}

console.log(`glTF version: ${version}, file size: ${length} bytes`);
console.log(`Meshes: ${(json.meshes || []).length}`);
console.log(`Nodes: ${(json.nodes || []).length}`);
console.log(`Skins: ${(json.skins || []).length}`);
if (json.skins) {
  for (const skin of json.skins) {
    console.log(`  Skin with ${skin.joints.length} joints`);
  }
}
console.log(`Animations: ${(json.animations || []).length}`);
for (const anim of json.animations || []) {
  const channelCount = anim.channels.length;
  console.log(`  "${anim.name}": ${channelCount} channels`);
}
console.log(`Materials: ${(json.materials || []).length}`);
