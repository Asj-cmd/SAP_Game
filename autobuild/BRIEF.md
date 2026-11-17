# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P5-1 — Menus

**Approach**
1. Audit `game/greybox/main_menu.gd` (title, team size, team-tell boxes, Play solo, Host + address, Join + code, Quit) and the in-game keys in `greybox_main.gd` `_unhandled_input` (F10 menu, Enter rematch, Esc mouse). Write the audit as a short list in PROGRESS.md.
2. **Settings** first, because pause and the menu both open it. Add one small loader/saver class (`PlayerSettings`, new `game/greybox/player_settings.gd`) on `user://settings.cfg`, the file `TeamTell` already uses. Put it in its own sections (`[controls]`, `[audio]`, `[keys]`) and leave TeamTell's section alone. Fields: mouse sensitivity (multiplier, default 1.0, range 0.25 to 3.0, applied on top of `ChaseCamera.MOUSE_SENSITIVITY`), Master / Effects / Music volume (linear 0 to 1, default 1 / 1 / 0.6), and the keyboard keys.
3. **Audio buses.** Create `godot/default_bus_layout.tres` with buses `Master`, `SFX` and `Music` (SFX and Music both feed Master). The volume sliders set them through `AudioServer.set_bus_volume_db(linear_to_db(v))`. P5-3 plays its sounds on these buses.
4. **Keybinds.** Keys are hard-coded in `LocalPlayerInput.poll` / `_read_travel` (W A S D, SPACE, SHIFT, E, R). Give the keyboard device a lookup from action to key: forward, back, left, right, jump, crouch, seize/free, free. Read it from `PlayerSettings`, with today's keys as the defaults. The settings screen rebinds a key by "click, then press a key"; Esc cancels and a "Reset to defaults" button restores them. Mouse buttons (grab LMB, throw RMB) and the gamepad stay fixed.
5. **Pause.** Esc in a match opens a pause panel (Resume, Settings, Leave to menu) and frees the mouse. Esc again or Resume closes it and captures the mouse. The sim is never paused (see below). While the panel is up, the player's input sends no travel (send a zero intent, the way the mouse-released case already does if it does; otherwise stop polling that seat).
6. **Results screen.** At `MATCH_END`, show a centred panel instead of the headline label. It shows the winner's family name (FamilyNames), the round score (for example 2–1), and each family's banked cash in the last round. Buttons: "Play again" (solo/host; it sets `_rematch_asked`, exactly as Enter does) and "Main menu" (same as F10). A guest sees "Waiting for the host" and "Main menu". Enter and F10 keep working. `headline_text()` must still return the same `MatchStatus.headline` string, because `playtest_pilot.gd` reads it.
7. **Lobby** (do it last; if the budget runs out, mark the task `[~]` with this left). It applies only when hosting FROM THE MENU (`_from_menu`). Do not send `MatchCommand.start()` straight away (greybox_main.gd ~line 846). Leave the world in `WAITING` and show a lobby panel instead:
   - the join code with a Copy button;
   - the seats from `link.lobby.seats`, grouped under each family's display name: a player's name, "open", or "bot" once started;
   - the mode, read-only: team size, round length, jail time, cash to win, rounds to win, all read from `level.mode`;
   - a "Fill empty seats with bots" checkbox (default on, sets `link.lobby.bots_enabled`);
   - Start, which runs the existing fill-then-start code;
   - Cancel, which goes back to the menu.

   A guest that joins a `WAITING` world sees "Joined, waiting for the host to start" until the confirmed phase leaves `WAITING`. The command-line `--host` / `--join` paths (net_smoke, `--pilot=host`) keep starting at once, unchanged. If a guest cannot join a `WAITING` world without changes in `net/` or `sim/`, drop the wait. Instead, show the same panel as a read-only roster on Tab during the match, and log why.
8. Add a "Settings" button to the main menu. Keep every existing control and its text: the pilot clicks "Play solo".

**Already decided**
- The sim never pauses, solo included: one code path, deterministic, and online play cannot pause anyway. Log it as REVIEW.
- Settings live in `user://settings.cfg` in new sections. Capture runs and `--pilot` ignore saved keybinds and sensitivity, as TeamTell does, so injected default keys still work.
- Rebinding covers the keyboard only. Mouse buttons and pads are fixed in v1.
- Only menu-hosted games wait in a lobby. CLI hosts auto-start. Log it.
- The results panel reads the confirmed world only (`link.outcome_world()`), never the predicted one.
- The look is plain: the existing dark shade, default Godot theme, the font sizes already in use. No new art. Family names always come from `FamilyNames`, never typed.
- Log in DECISIONS.md: the pause semantics (REVIEW), the default volumes (REVIEW), the lobby-only-from-menu rule, the settings file layout.

**Files likely touched**
`godot/game/greybox/main_menu.gd`, `godot/game/greybox/greybox_main.gd`, `godot/game/greybox/local_player_input.gd`, `godot/game/greybox/chase_camera.gd`, `godot/game/greybox/match_status.gd` (results text only), `godot/game/greybox/player_settings.gd` (new), `godot/game/greybox/pause_menu.gd` / `settings_panel.gd` / `lobby_panel.gd` / `results_panel.gd` (new, one file each or fewer), `godot/default_bus_layout.tres` (new), `godot/project.godot` (bus layout path if needed), `HOW_TO_PLAY.md` (Esc = pause, settings), `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- The full `node autobuild/verify.mjs`, run ONCE at the end just before committing, prints `VERIFY: healthy`. That covers 17 suites at their pinned counts, symmetry exact, bot match 3v3 + 1v1, tick budget, and net_smoke (which proves the CLI host/guest path still auto-starts).
- No new test file: this is presentation, and the Lobby model in `net/` is unchanged.
- No frame captures.

**Do NOT**
- Pause or slow the sim, or add a pause command to `sim/` or the network.
- Change `net/lobby.gd` rules or the seat/rejoin handshake (P0-5d). Do not change the join-code format.
- Rebind mouse or pad, or add Steam invite UI (P6-4).
- Build the HUD bar (P5-2) or play any sound (P5-3). This task only creates the buses and sliders.
- Restyle with custom art, fonts or animated menus. Do not run bot tuning or sweeps.

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
