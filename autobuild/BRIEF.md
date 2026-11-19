# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

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
