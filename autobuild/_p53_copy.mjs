import { copyFileSync, mkdirSync } from "node:fs";
const K = "autobuild/Incoming/kenney/";
const O = "godot/art/audio/";
mkdirSync(O + "sfx", { recursive: true });
mkdirSync(O + "music", { recursive: true });
const map = [
  ["step_wood_1", "impact-sounds", "footstep_wood_000"], ["step_wood_2", "impact-sounds", "footstep_wood_001"],
  ["step_wood_3", "impact-sounds", "footstep_wood_002"], ["grab_1", "rpg-audio", "cloth1"], ["grab_2", "rpg-audio", "cloth2"],
  ["throw", "rpg-audio", "cloth3"], ["seize_thump", "impact-sounds", "impactSoft_heavy_000"], ["seize_cloth", "rpg-audio", "cloth4"],
  ["free", "rpg-audio", "metalLatch"], ["land", "impact-sounds", "impactSoft_medium_000"], ["cash_1", "rpg-audio", "handleCoins"],
  ["cash_2", "rpg-audio", "handleCoins2"], ["sting", "interface-sounds", "bong_001"], ["tick", "interface-sounds", "tick_001"],
  ["ui_click", "interface-sounds", "click_001"],
];
for (const [n, pack, src] of map) copyFileSync(`${K}${pack}/Audio/${src}.ogg`, `${O}sfx/${n}.ogg`);
console.log(map.length, "copied");
