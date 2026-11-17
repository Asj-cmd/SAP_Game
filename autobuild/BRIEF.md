# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P5-3 — Audio

**Approach**
1. Fetch the sounds with `node autobuild/fetch_kenney.mjs <slug>` (it refuses non-CC0). Try `impact-sounds`, `interface-sounds` and `rpg-audio`; that last one has footsteps, cloth and coins. They unpack into the gitignored `autobuild/Incoming/kenney/`. Copy ONLY the dozen or so `.ogg` files used into `godot/art/audio/sfx/`, with plain names (`step_wood_1.ogg`, `grab.ogg`, ...).
2. For the music: one calm CC0 loop (elevator or lounge muzak, which fits the deadpan tone) from OpenGameArt, with its CC0 licence checked on the page. Put it in `godot/art/audio/music/`. If no CC0 loop can be fetched, ship no music, log it, and carry on: this is not a block.
3. Record every file in `ASSETS.md` (name, source URL, licence, date, modified?) and `CREDITS.md`.
4. Build `GameAudio` (new `godot/game/audio/game_audio.gd`, a Node owned by `greybox_main`). It holds a data table: event → list of streams, volume dB and bus. It picks a variant with its own `RandomNumberGenerator`, never the sim's. It keeps a small pool of `AudioStreamPlayer3D` (max 8 at once) for world sounds and one `AudioStreamPlayer` each for UI and music. A missing file plays nothing (`ResourceLoader.exists`, the art fallback rule).
5. Hook the events where the presentation already detects them in `greybox_main.gd` `_animate` / `_act`:
   - grab, throw, seize ("caught": a plain thump and a cloth rustle), free;
   - landing after a jump;
   - a deposit (a family's `score_for` going up: a soft cash or paper sound);
   - round end and match end (one short alarm-ish sting, `MatchStatus` phases);
   - the countdown ticks;
   - UI clicks in the menu and the P5-1 panels.
   Footsteps: per drawn body, one step per ~70 cm travelled on the ground while not jailed, wood or tile by room finish if that is cheap, else one set. Only within 25 m of the camera.
6. Buses: `SFX` and `Music` from `godot/default_bus_layout.tres`. If P5-1 has not created it, create it here with Master/SFX/Music and hook the P5-1 volume sliders if they exist.

**Already decided**
- Ordinary household sounds only (D2): footsteps on wood or tile, cloth, paper or cash, a door thud, a plain buzzer or alarm sting. No boings, whooshes, cartoon or voice sounds. Log the picks as REVIEW.
- Music plays in the menu and lobby at full Music volume and at −12 dB under a match. REVIEW.
- Door sounds: the doors are static open meshes with no open/close event, so there are no door sounds in v1 (log it). Unless the sting uses a door thud.
- Files are `.ogg` as shipped, not re-encoded. Only the used files go into git, never whole packs.
- A body you cannot see still makes its sounds (that is information a player hears), but nothing is louder than the player's own steps.
- Headless runs (tests, net_smoke runs the game scene `--headless`) must stay error-free with the dummy audio driver. Check the verify output for new warnings.

**Files likely touched**
`godot/game/audio/game_audio.gd` (new), `godot/game/greybox/greybox_main.gd`, `godot/game/greybox/main_menu.gd` (UI clicks, menu music), `godot/art/audio/sfx/*.ogg` and `godot/art/audio/music/*.ogg` (new), `godot/default_bus_layout.tres` (exists after P5-1; else new), `godot/export_presets.cfg` (only if `.ogg` is filtered out of the export), `ASSETS.md`, `CREDITS.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- The full `node autobuild/verify.mjs`, run ONCE at the end just before committing, prints `VERIFY: healthy`: all suites at pinned counts, symmetry exact, bot match unchanged (audio is presentation; numbers must not move), net_smoke agrees.
- No new test file.
- No frame captures.
- In PROGRESS.md: list each event → file, and the ASSETS.md rows.

**Do NOT**
- Use paid packs, AI-generated audio or credits, or anything not clearly CC0 (D10). No NC/ND or unclear licences.
- Play sounds from `sim/`, add sim events for audio, or read the sim's RNG.
- Add spatial reverb or effects buses, or a mixer UI beyond the P5-1 sliders.
- Commit the downloaded zips or whole packs. Do not write audio tests. Do not run captures, sweeps or bot work.
