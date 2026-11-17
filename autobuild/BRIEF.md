# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P5-2 — HUD: a fighting-game style top bar

**Approach**
1. Add the pure split function to `MatchStatus`: `static func cash_split(first: int, second: int) -> float`. It returns the first family's share of the bar: 0.5 when both are 0, otherwise `first / (first + second)`. So it is 1.0 when the second has nothing and 0.0 when the first has nothing.
2. Write the table-driven test `godot/tests/match_status_test.gd` (new; copy the harness shape of `family_names_test.gd`, with `EXPECTED_CHECKS`). Rows: 0/0 → 0.5, 1/0 → 1.0, 0/4 → 0.0, 3/1 → 0.75, 2/2 → 0.5, 1/3 → 0.25. Add `"match_status_test": <count>` to `autobuild/test_baseline.json`.
3. Build `MatchHud` (new `godot/game/greybox/match_hud.gd`, a `Control` on the existing `_text_layer`). One bar runs across the top, about 60 % of the screen wide and 28 px high. The first family's colour fills from the left up to `cash_split`, and the second family's fills the rest from the right.
   - At each end: the family's display name (`FamilyNames.name_of`) and its banked cash (`world.score_for`) as "n / target" (`world.mode.score_to_win()`), with round-win pips (filled up to `round_wins_for`, out of rounds to win).
   - In the middle, over the bar: the round number and the clock (reuse `MatchStatus._clock`; make it public if needed).
   - Mark your own family with a small "YOU" under its name.
4. Below the bar, only when true: "CARRYING CASH"; when jailed, a large centred "JAILED  12" counting down `capture_ticks_remaining`; and the rescue prompt "[E] Free <member>" when a jailed teammate is within free reach. For the prompt, add a public read-only helper on `LocalPlayerInput` that reuses `_nearest` + `_is_rescue_target` with the same range `drain` uses. Show the key from the P5-1 keybinds if they exist, else "E".
5. In `greybox_main.gd` `_update_hud`, replace the `_status` label with `MatchHud.update(truth, level, mine)`. It shows when `link.is_ready()` and the debug HUD is off. Keep `_headline` for the countdown and round results (and P5-1's results panel, if it is there). F1 still swaps to the debug HUD.
6. Search `godot/game` for any visible "Team A"/"Team B"/"team_a" text left on screen and route it through FamilyNames.

**Already decided**
- The first family (`level.teams[0]`, team_a) is ALWAYS on the left, on every machine, like player 1 in a fighting game, so the bar never mirrors between players. Your own side is marked "YOU". REVIEW.
- The colours are `ArtTheme.current().family_colours` (the same ones `TeamTellOverlay` uses). The bar background is dark grey at 60 % opacity. The split eases towards its new value over about 0.3 s, drawn only.
- The cash counted is banked cash this round (`score_for`), not cash being carried.
- The teammates-only minimap is the existing D3 option (b) in `TeamTellOverlay`. It stays as it is and stays OFF by default (P2-4). Do not turn it on and do not build a second one.
- `MatchStatus.line` may stay for the debug HUD or be deleted if nothing calls it.
- Log in DECISIONS.md: the fixed left/right order (REVIEW), the bar layout (REVIEW).

**Files likely touched**
`godot/game/greybox/match_status.gd`, `godot/game/greybox/match_hud.gd` (new), `godot/game/greybox/greybox_main.gd`, `godot/game/greybox/local_player_input.gd` (read-only rescue-target helper), `godot/tests/match_status_test.gd` (new), `autobuild/test_baseline.json`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- `match_status_test` passes with its six rows (plus any edge rows) and is pinned in `test_baseline.json`.
- The full `node autobuild/verify.mjs`, run ONCE at the end just before committing, prints `VERIFY: healthy` with 18 suites.
- No frame captures (the task says so).

**Do NOT**
- Test anything beyond the split function: no HUD layout or label tests.
- Read the predicted world for the cash or the clock (use the confirmed `truth`). Do not write to the sim from the HUD.
- Build a new minimap, enemy markers, a kill feed, or any cartoon effects, flashes or confetti (D2).
- Type a family name into the UI or a test. Tests compare numbers only.
- Do P5-1's menus or P5-3's sounds here. Do not run captures, sweeps or bot work.

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
