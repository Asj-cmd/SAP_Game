# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT3-1 — Music only outside matches, and a quirky track

**Approach**
1. In `GameAudio` (`godot/game/audio/game_audio.gd`), replace the duck (`set_in_match`:
   −12 dB in a match) with a fade. Going into a match, tween `_music.volume_db` down to −80 over
   1.0 s, then `stream_paused = true`. Going to the menu, lobby or results, unpause and tween
   back to `MUSIC_MENU_DB` over 1.0 s.
2. Add one pure static rule, `GameAudio.music_wanted(screen: StringName) -> bool`, with screens
   `&"menu"`, `&"lobby"`, `&"results"` → true and `&"match"`, `&"end_sequence"` → false. Unknown
   screens → false. Replace `set_in_match(bool)` with `set_screen(screen)`, which calls the rule.
   Update the two call sites in `greybox_main.gd` (lines ~393 and ~1471). Add a third where the
   results panel is shown (`results_panel.gd` / wherever GreyBoxMain opens it at MATCH_END) and
   one where the lobby opens (`lobby_panel.gd`).
3. The win/lose jingle (`_match_end_jingle`) still plays when the match ends, on the Music bus,
   over the fade-in. Don't route it through the music player.
4. Leave PT2-7 a hook: when PT2-7 adds the end sequence, it calls `set_screen(&"end_sequence")`
   and then `&"results"`. Say so in a comment.
5. Music: search OpenGameArt CC0 first (with `node autobuild/fetch_url.mjs`, since the web fetcher
   gets 403 there), then Kenney, then freepd.com (CC0) or incompetech (CC-BY 4.0, credit needed).
   Search terms: "pizzicato", "sneaky", "heist", "spy", "caper", "tiptoe". Download three into
   `godot/content/music/candidates/`. Measure each with `autobuild/ogg_info.mjs` and
   `godot/tools/audio_probe.gd --ends` (trailing silence). Convert MP3s with
   `tools/decode_audio.gd` + `autobuild/encode_ogg.mjs` (the PT2-4 path).
6. Copy the pick to `godot/content/music/menu.ogg`. Point `MUSIC_PATH` there, and set
   `MUSIC_LOOP_END` from the measured end of its sound (0 if it has no trailing silence).
7. Move `godot/art/audio/music/loop.ogg` (and its `.import`) to `godot/content/music/candidates/`
   with `git mv`. Mark its ASSETS row "candidate, not shipped". Remove its CREDITS.md and
   `godot/content/credits.md` lines because nothing ships it.
8. `godot/export_presets.cfg`: add `content/music/menu.ogg` to `include_filter`, and add
   `content/music/candidates/*` to `exclude_filter`. If a candidate is over ~5 MB, add a
   `.gitignore` line for it and say so.
9. Docs: add a "Changing the menu music" section to HOW_TO_PLAY.md (file `godot/content/music/menu.ogg`,
   OGG Vorbis, loops from start to end, rebuild with `node autobuild/build.mjs`), modelled on
   "Changing the jail sound". Add three rows to ASSETS.md (two "candidate, not shipped") and one
   to CREDITS.md and `godot/content/credits.md`, each with author, licence, URL and where the proof
   page is saved (gitignored `autobuild/Incoming/music/...`, like PT2-4).

**Already decided**
- Fade 1.0 s each way. The music pauses (it doesn't restart) during a match, so it resumes where
  it was.
- How to pick without listening: the tempo the source states (90–120 BPM preferred), a loop of
  at least 60 s, and a description that says pizzicato/sneaky/playful. Reject anything described
  as jazz, lounge, elevator or "hold". Log the pick in DECISIONS.md as **REVIEW** (the user will
  listen), with the other two named as one-file swaps.
- CC-BY only if no suitable CC0 is found, and then credited.

**Files likely touched**
- `godot/game/audio/game_audio.gd`, `godot/game/greybox/greybox_main.gd`,
  `godot/game/greybox/results_panel.gd`, `godot/game/greybox/lobby_panel.gd`
- `godot/content/music/menu.ogg` (new), `godot/content/music/candidates/` (new, 3 files plus the old loop)
- `godot/export_presets.cfg`, `.gitignore` (only if needed)
- `godot/tests/music_rule_test.gd` (new: the table-driven `music_wanted` cases), pinned in
  `autobuild/test_baseline.json`
- `HOW_TO_PLAY.md`, `ASSETS.md`, `CREDITS.md`, `godot/content/credits.md`, `DECISIONS.md`,
  `PROGRESS.md`, `PLAN.md`

**Done means**
- `music_rule_test` passes: menu, lobby and results are true; match, end_sequence and an unknown
  screen are false.
- A headless `--menu` run and a `--solo` run (about 30 s each, through `autobuild/run_game.mjs`)
  print no script errors.
- `grep -rn "loop.ogg" godot/game` finds nothing.
- Full `node autobuild/verify.mjs` once at the end, just before committing: `VERIFY: healthy`, new
  test pinned, net_smoke agrees. No frames.

**Do NOT**
- Don't use meme clips or anything with an unclear, NC or ND licence, and don't spend money or log in to anything.
- Don't delete the jazz file (move it).
- Don't touch the sim, bots, or other sounds (PT3-2 does the cash sounds).
- Don't shoot frames, and don't build the PT2-7 end sequence here.

## PT3-2 — Cash sounds are paper

**Approach**
1. Today: `grab` = `grab_1/2.ogg` (rpg-audio cloth1/2) fires in `greybox_main.gd:1663`. `cash` =
   `cash_1/2.ogg` (rpg-audio handleCoins) is the deposit sting (`game_audio.gd:184`). The coin
   clicks are probably the "gun being loaded" the user hears when they drop cash at home. A plain
   drop and a bundle hitting the ground have no sound at all yet. `throw` plays `throw.ogg`.
2. Find CC0 candidates: Kenney packs through `node autobuild/fetch_kenney.mjs` (e.g. "rpg-audio"
   has bookFlip/bookPlace, "impact-sounds" has soft thuds), and OpenGameArt CC0 through
   `autobuild/fetch_url.mjs`. Apply the reject list from the task (click, latch, snap, cock,
   reload, metal) to title and description.
3. Trim each to under 0.6 s with no leading silence, and normalise its peak to the other effects
   (measure with `godot/tools/audio_probe.gd`). Use the PT2-4 decode/encode path for non-OGG sources.
4. Move the replaced files with `git mv` to `godot/art/audio/sfx/retired/` (grab_1, grab_2,
   cash_1, cash_2, plus their `.import`s). Put the new files under the same names, so `EVENTS`
   in game_audio.gd keeps its event names and file lists: `grab_1/2` = paper rustle/flutter,
   `cash_1/2` = soft paper-bundle thud.
5. Add two events, each with one file: `drop` (`drop.ogg`, the thud) and `bundle_land`
   (`bundle_land.ogg`, a quieter thud, may be the same source pitched or trimmed differently).
   In `greybox_main.gd` around line 1654: when `was_carrying` ends and the bundle is in flight
   WITHOUT sideways speed, play `drop` at the carrier. When any bundle goes from `in_flight` to not
   in flight, play `bundle_land` at the bundle's position. That needs a per-bundle `in_flight`
   tracker read from the confirmed world, like `_anim_carrying`, and it is presentation only. A
   deposit keeps playing `cash`.
6. Docs: add a "Cash sounds" line to HOW_TO_PLAY.md (which files under `godot/art/audio/sfx/`,
   OGG, keep the names). Add ASSETS.md rows (old rows marked "retired, not shipped") and
   CREDITS.md + `godot/content/credits.md` rows with the CC0 proof.

**Already decided**
- Event names stay. Two new events, `drop` and `bundle_land`, all on the default SFX (Effects) bus.
- Levels start at the old rows' dB (grab −4, cash −4); `drop` −5, `bundle_land` −7.
- Log the picks in DECISIONS.md as **REVIEW** (unheard).
- Make sure `retired/` is not exported: `art/audio/sfx/retired/*` goes in `exclude_filter` in
  `godot/export_presets.cfg`.

**Files likely touched**
- `godot/art/audio/sfx/` (grab_1, grab_2, cash_1, cash_2 replaced; drop.ogg and bundle_land.ogg new;
  `retired/` new)
- `godot/game/audio/game_audio.gd` (two EVENTS rows), `godot/game/greybox/greybox_main.gd` (drop + landing hooks)
- `godot/export_presets.cfg`, `HOW_TO_PLAY.md`, `ASSETS.md`, `CREDITS.md`, `godot/content/credits.md`,
  `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`

**Done means**
- Every new file is under 0.6 s, measured with `ogg_info.mjs` (numbers in PROGRESS.md).
- A headless `--solo --anim-log` run (~75 s through `run_game.mjs`) prints no script errors.
- Full `node autobuild/verify.mjs` once at the end, just before committing: `VERIFY: healthy`, test
  pins unchanged. No frames. No new test file (audio is never tested, `godot/CLAUDE.md`).

**Do NOT**
- Don't use anything metallic or click-like, or anything not CC0. Don't make accounts.
- Don't delete the old files (retire them).
- Don't change sim, carry, throw physics or the snapshot. The landing is detected from the
  confirmed state, never written back to it.
- Don't retune the other sounds, and don't touch the music (PT3-1).
- Don't shoot frames.
