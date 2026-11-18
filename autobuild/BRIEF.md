# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-7 — Menu and HUD polish

REDO (from PT4-6):
REDO: The lineup frames look right (hands end at mid-thigh, small mitts, nothing sticks out). The carry frames do not: in `autobuild/frames/pt4_6/dad_carry_1.png` the carrying dad's hands show as a flat cream slab standing across the FRONT face of the bundle, fingers reaching into its top half; in `dad_carry_2.png` his raised palm is a flat slab cut into the bundle's side. The bundle there was a prop at `hands_point` + 6, the same place play puts it, so the live carry likely clips the same way. Fix first, numbers only, no new frames: extend `tools/arm_probe.gd` to print each member's fingertip height in `carry_idle` against the bundle's bottom (`hands_point` + `CARRY_HAND_LIFT`). If fingertips sit more than 2 cm above that bottom, tip the hands back at the wrist in the carry pose (`game/art/figure_animator.gd`, the `hand_l` / `hand_r` bones after the arm IK) so the palms lie under the bundle; do not raise `CARRY_HAND_LIFT` (that sinks nothing but floats the bundle) and do not touch the sim. Write the before/after fingertip numbers in PROGRESS.md under PT4-7. Then do PT4-7.

**Approach**
1. Main menu (`main_menu.gd` ~line 174): remove the team-tell CheckBox block (`_tell_boxes`, `TeamTell.OPTIONS` loop) and add the same rows to `settings_panel.gd` under a heading "Team tell (experiment)". Same `TeamTell.current().set_option` calls; the F5–F8 keys are unchanged. Settings opens from both the menu and pause, so it shows in both.
2. Host row: Host button alone by default. A small "Advanced" toggle button (SMALL_BUTTON style) under it shows/hides the address LineEdit and the Tailscale note. The address is still pre-filled exactly as now, so Host with Advanced closed behaves the same as today.
3. Menu backdrop crisp: delete the charcoal wash `ColorRect` (`main_menu.gd` ~line 88). The fog comes from `WorldBackdrop` (`world_backdrop.gd` ~line 140: depth fog from `theme.haze_from`, the orbit camera is ~6900 away). While the menu backdrop shows (`_show_menu_backdrop` in `greybox_main.gd` ~line 996), use the environment with `fog_enabled = false`; restore it when a match starts. Keep the card readable with the card's own panel, not a full-screen wash.
4. One button/card finish in `ui_theme.gd`: a soft drop shadow on `CARD` and on buttons (StyleBoxFlat `shadow_size` 4, `shadow_offset` (0, 3), `CHARCOAL_SOFT`), hover = existing `HOVER_SCALE` plus a slightly lighter fill, press = `PRESS_SCALE` plus shadow offset 1. Remove any per-screen StyleBox overrides that duplicate this (grep `add_theme_stylebox_override` in `game/greybox/`).
5. Results card (`results_panel.gd`): one title line, then a two-column row per family (name in family colour, rounds won, cash banked), buttons at the bottom aligned; consistent margins from `PANEL_MARGIN`. Keep `ResultsPanel.title_for` text rules (PT3-3: "<NAME> WINS THE MATCH").
6. Capture one set at the end (below), look, fix at most once.

**Already decided**
- Team tell lives only in Settings, not on the menu. Not REVIEW.
- "Advanced" collapsed by default every launch (not saved). Log it, REVIEW.
- Menu backdrop: no fog and no wash; log REVIEW.
- Shadow/hover/press numbers above; all in `UiTheme`, not per screen. Log REVIEW.
- Deadpan: no bounce, no confetti, no colour flashes; names only from `FamilyNames` (PT3-3).

**Files likely touched**
`godot/game/greybox/main_menu.gd`, `settings_panel.gd`, `ui_theme.gd`, `results_panel.gd`, `greybox_main.gd` (`_show_menu_backdrop`), `world_backdrop.gd` (only if a fog switch is needed there), `lobby_panel.gd` / `pause_menu.gd` only to drop duplicate style overrides. REDO: `godot/game/art/figure_animator.gd`, `godot/tools/arm_probe.gd`. `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- Menu shows no team-tell checkboxes; Settings shows all `TeamTell.OPTIONS` and toggling one changes `TeamTell.current()`; Host with Advanced closed starts hosting with the pre-filled address.
- REDO numbers in PROGRESS.md (fingertips at or below bundle bottom + 2 cm for every member that carries over its head).
- Full `node autobuild/verify.mjs` run ONCE at the end, just before committing: healthy, every suite at its pin.
- Frames: ONE capture set at the end, `--capture-screen=` menu, settings, pause, lobby, hud, results (into `autobuild/frames/pt4_7/`). Menu: houses crisp with no grey haze or dark wash, no checkboxes, Host + Advanced only. Settings: the team-tell rows present. Every card/button: same shadow and finish. Results: tidy aligned rows, family colours, correct title. At most one redo.

**Do NOT**
- Touch the sim, net messages, team-tell logic, or the cash-bar/HUD layout PT4-4 settled.
- Add a test file (UI is never tested). No bots, no sweeps.
- Restyle every screen from scratch or add new fonts/colours outside `UiTheme`.
- Remove fog from matches (it hides the far plane there).

## PT2-7 — Match end sequence

**Approach**
1. New `godot/game/greybox/end_sequence.gd` (`EndSequence`, a Node): started by `greybox_main.gd` when the confirmed world first reaches `MATCH_END` (today `_update_hud` ~line 2644 shows `_results` at once). Results now open only when the sequence ends or is skipped.
2. Camera: its own Camera3D circles the winning family's row (their current drawn positions, or their spawn row via the PT4-2 `FamilyLineup.frame` helper; pick the row: winners lined up on their front lawn is simplest and always clear of walls), radius ~450, height ~170, one half-turn over 5 s, looking at a point 120 above the row's middle. Draw-only: stand the drawn bodies there, never move sim bodies.
3. Poses: winners hold the cash overhead in `carry_idle` with a bundle prop each (presentation-only bundle meshes), stiff, no extra animation. Losers stand still in rest pose a few metres behind, blank. A drawn match: no sequence, go straight to results.
4. Title: big `HUD_BIG` line centred upper third. Lines in ONE file, new `godot/content/end_titles.cfg`, parsed like `family_names.cfg` (`win=THE {name} GOT RICH.`, `lose=THE {name} GOT ROBBED.`). `{name}` = `FamilyNames` display name of the winners (win line) or of the viewer's own family (lose line), upper-cased. Since every display name ends in "Family" (PT3-3) the "s" case is moot, but use the template as written, no plural logic. Add the .cfg to the export `include_filter` (like `family_names.cfg`, DECISIONS P5-0).
5. Audio: move the jingle call (`GameAudio._match_end_jingle`, the "one call site" at ~line 236) to the sequence start; `GameAudio.set_screen(&"end_sequence")` while it runs (silent music), `&"results"` when the panel opens; add `&"end_sequence"` to `GreyBoxMain._music_screen` before `&"results"`.
6. Skip: any key or mouse button after 0.5 s ends it and opens results. Length 5 s.
7. Guests run the same sequence from their own confirmed world. Dedicated host: no sequence. `--capture-screen=results` keeps working (skips the sequence); add `--capture-screen=end` for the frames.

**Already decided**
- 5.0 s, half orbit, skippable after 0.5 s. REVIEW.
- Lines exactly "THE {name} GOT RICH." / "THE {name} GOT ROBBED." in `content/end_titles.cfg`. REVIEW.
- Winners in `carry_idle` holding a prop bundle; losers rest pose. REVIEW.
- Drawn match skips the sequence. Log.
- Rematch (Enter) during the sequence: treat as skip, then normal results flow.

**Files likely touched**
`godot/game/greybox/end_sequence.gd` (new), `godot/content/end_titles.cfg` (new), `godot/game/greybox/greybox_main.gd`, `godot/game/audio/game_audio.gd`, `godot/game/greybox/family_names.gd` (reuse its parser), `godot/game/greybox/results_panel.gd` (only if open timing needs a hook), `godot/game/debug/` frame-capture file that implements `--capture-screen` (grep `capture-screen`), `godot/export_presets.cfg`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- `music_rule_test` still passes with `&"end_sequence"` silent (extend its table by one case if it lists screens; no new test file).
- A headless solo run to MATCH_END prints no script errors (`node autobuild/run_game.mjs`).
- Full `node autobuild/verify.mjs` ONCE at the end: healthy; net_smoke hashes agree (proves no sim/net change).
- Frames: ONE set at the end into `autobuild/frames/pt2_7/`: `--capture-screen=end` from the winners' view at ~1 s and ~3 s, and from the losers' view once, plus `--capture-screen=results`. Must show: the winning family in a row holding bundles overhead, losers blank behind, title readable with the right family name, no walls between camera and bodies; results card after. At most one redo.

**Do NOT**
- Change the sim, MatchPhase, snapshot or network messages; no new sim timer.
- Add confetti, particles, cheering, faces or extra animation clips.
- Copy another game's victory screen.
- Hard-code the lines or names in code.
- Touch bots or run sweeps.

## PT2-8 — Funnier hair

**Approach**
1. Hair is generated in `godot/tools/rerig_character.gd` `_build_hair` (~line 690); per-body args are in `autobuild/rerig_family.mjs` (`male` / `casual` = the boys' bodies, mohawk 8 / 6; `dress` = mom, beehive; `alt` = elder girl, `pigtails_long`; `tank` = younger girl, `pigtails_short`; `shirt` = dad).
2. Mohawk: raise `--hair-height` 8 → 16 (elder, `male`) and 6 → 13 (younger, `casual`); widen the ridge base (`_hair_arc` half-width 0.24 → 0.32) and keep the crest profile. Clearly bigger at 20 m.
3. Mom: the funnier pick is the **tall stiff beehive** (it is a deadpan absurd tower, reads as a silhouette at any distance, and the lathe already exists; a perm would read as a lumpy helmet at chase distance). Make it about 34 cm above the crown (from 21), slightly wider in the middle (0.98 → 1.05 r) and a rounded top, lean back 12° (from 8°) so the carried bundle sits more in front of it.
4. Daughters: "two shabby, uneven pigtails". Make the two sides different: one longer and lower, one shorter, higher and sticking out more; different tilt each side (e.g. 6° vs 22°), different radii (±25 %), and a slight wobble by splitting each bunch into two offset blobs. Elder (`pigtails_long`): left reaches shoulder + 8 cm, right stops ~6 cm higher and splays out. Younger (`pigtails_short`): left at 25° up, right at 5° and 30 % shorter. Keep it deterministic (fixed numbers, no random).
5. Re-run only the changed bodies: `node autobuild/rerig_family.mjs --only=male,casual,dress,alt,tank`, then import (as P2-6 did; see `family_lineup.mjs --import`). Dad (`shirt`) is not rebuilt and stays byte-identical.
6. Check triangles stay under the 5,000 per body budget (bake prints them). Capture the one lineup.

**Already decided**
- Mom = beehive, ~34 cm, lean 12°. REVIEW.
- Mohawk 16 / 13 high, base 0.32. REVIEW.
- Uneven pigtails per the numbers above, same idea for elder and younger. REVIEW.
- Colours unchanged (`FamilyMember.hair_colour`); same in both families. Hair stays plain solid shapes in the figure material (P2-6, D2).
- Hair above 180 is fine (drawn height is the body's, `_body_box`; STYLE §2.2).

**Files likely touched**
`godot/tools/rerig_character.gd`, `autobuild/rerig_family.mjs`, regenerated `godot/art/characters/figure_lp_{male,casual,dress,alt,tank}.*` (check the exact folder with Glob before writing), `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.

**Done means**
- Bake output: every rebuilt body under 5,000 triangles; dad's files unchanged in `git status`.
- Full `node autobuild/verify.mjs` ONCE at the end: healthy, render counters within limits.
- Frames: ONE lineup at the end, `node autobuild/family_lineup.mjs` into `autobuild/frames/pt2_8/` (front and 20 m are the ones to judge). Must show: both boys' mohawks clearly bigger than in `autobuild/frames/pt4_6/lineup_front.png`, mom's beehive a tall tower, both girls' pigtails visibly uneven left vs right, dad unchanged, no hair through faces. At most one redo.

**Do NOT**
- Change dad, faces (still blank), outfits, bone scales or the carry code.
- Add textures, strands, alpha, physics or new materials.
- Touch collision, the sim body height, or bots.
- Copy a known character's hairdo.
