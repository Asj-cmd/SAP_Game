import { appendFileSync, readFileSync, writeFileSync } from "node:fs";
appendFileSync("ASSETS.md", `
## Audio (P5-3) - Kenney, CC0 1.0, fetched 2026-11-17, unmodified .ogg, only the used files copied to godot/art/audio/sfx/
Packs: impact-sounds (https://kenney.nl/assets/impact-sounds), interface-sounds (https://kenney.nl/assets/interface-sounds), rpg-audio (https://kenney.nl/assets/rpg-audio). Zip hashes in autobuild/Incoming/kenney/<slug>/SOURCE.txt (gitignored).

| File | From | Event |
|---|---|---|
| step_wood_1-3 | impact-sounds footstep_wood_000-002 | footsteps |
| grab_1, grab_2 | rpg-audio cloth1, cloth2 | grab |
| throw | rpg-audio cloth3 | throw |
| seize_thump, seize_cloth | impact-sounds impactSoft_heavy_000; rpg-audio cloth4 | caught |
| free | rpg-audio metalLatch | free an ally |
| land | impact-sounds impactSoft_medium_000 | landing |
| cash_1, cash_2 | rpg-audio handleCoins, handleCoins2 | deposit |
| sting | interface-sounds bong_001 | round / match end |
| tick | interface-sounds tick_001 | countdown |
| ui_click | interface-sounds click_001 | every button |

Music: none shipped (no CC0 loop fetched; GameAudio plays res://art/audio/music/loop.ogg if one is added).
`);
appendFileSync("CREDITS.md", `
## Sound effects

- Footsteps, impacts, cloth, coins, clicks and bell: Kenney (kenney.nl) Impact Sounds, Interface Sounds and RPG Audio, CC0 1.0.
`);
appendFileSync("DECISIONS.md", `| 2026-11-17 | P5-3 | **REVIEW** Audio: ordinary Kenney CC0 sounds only (wood footsteps, one set; cloth for grab/throw/caught; a latch for free; coins for deposit; a plain bell for round/match end; tick for countdown; one click for every button). World sounds attenuated by hand to 25 m, other bodies -5 dB under own. GameAudio is presentation-only with its own RNG | D2 deadpan | Edit GameAudio.EVENTS |
| 2026-11-17 | P5-3 | No door sounds (doors have no open/close event). No music shipped: no CC0 loop was fetched; GameAudio plays art/audio/music/loop.ogg (0 dB menu, -12 dB in match) when one exists | Not a block | Drop a file in |
`);
let p = readFileSync("PLAN.md", "utf8");
p = p.replace("- [ ] **P5-3 Audio.**", "- [x] **P5-3 Audio.**");
writeFileSync("PLAN.md", p);
let b = readFileSync("autobuild/BRIEF.md", "utf8");
b = b.replace(/## P5-3 — Audio[\s\S]*?(?=\n## |$)/, "");
writeFileSync("autobuild/BRIEF.md", b);
