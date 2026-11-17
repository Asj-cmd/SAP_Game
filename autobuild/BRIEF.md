# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P4-7 — Verb readability audit by frames

**Approach**
1. Do NOT capture anything. Open, with Read, the frames earlier verb tasks already made:
   `autobuild/frames/p4_1/panic_sheet.png`, `p4_2/*` (carry, carry crouch, carry jump, crouch,
   jump run/stand, throw, panic), `p4_3/jail_*`, `p4_4/jail_*`, `p4_5/*` (throw, drop, fence
   throw), and `p4_8/panic_sheet.png` once P4-8 has made it. About 25 images: open one or two per
   verb, not all if the first answers it.
2. For each D9 verb (walk, panic run, jump + landing wobble, crouch-walk, grab, carry overhead,
   throw, seize, free, jail run-in-place, standing still), write one PROGRESS line: readable at a
   glance yes/no, and what is wrong if no. Judge against D2/D9 (deadpan, no acting, arms up when
   panicking, cash stiffly overhead).
3. Fix only small presentation defects you find (a clip pick in `FigureAnimator.base_clip`, a
   pose number, a missing one-shot), at most two, each a few lines in `godot/game/art/`. List
   anything bigger as a follow-up in PROGRESS; do not start it.
4. If nothing needs fixing, the audit itself is the deliverable: tick with the table.

**Already decided**
- The frames are evidence from before P4-8 (except the P4-8 sheet): a panic sheet showing 648 is
  the old boost, not a defect now.
- Seize and free have no sheet of their own in `p4_*`. Use `autobuild/frames/p2_3/` (seize,
  free), if present. If there is no frame, write "not seen". Do not shoot one.
- Any fix that changes a pose or clip is logged in DECISIONS.md as REVIEW.

**Files likely touched**
- `PROGRESS.md`, `PLAN.md`; maybe `godot/game/art/figure_animator.gd`,
  `godot/tools/build_figure_anims.gd` (only if an arm pose needs a number changed; re-run it to
  rebuild `art/characters/figure_anims.res`)

**Done means**
- A per-verb table in PROGRESS (verb, frame looked at, readable?, what is wrong).
- If code changed: `node autobuild/verify.mjs` once at the end, `VERIFY: healthy`. If only docs
  changed, no verify run is needed (no code touched).

**Do NOT**
- New captures, contact sheets, follows or pilots (testing diet: P4-7 is not one of the four
  capture tasks).
- Sim changes, new verbs, ragdoll/knockback, bot work.
- Rework animations wholesale or re-pick clips the user has not asked about.
