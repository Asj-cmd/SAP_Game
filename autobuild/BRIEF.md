# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## PT4-6 — Hands and arms

**Approach**
1. Measure before changing. In the idle rest pose, print the following for each of the six members
   (dad, mom, elder_girl, elder_boy, younger_girl, younger_boy): wrist height (`hand_*` bone
   origin) / drawn height, fingertip height / height, hand length / height and palm width / height.
   Use a temporary print in a headless tool run that builds the figures through
   `ArtTheme.shape_figure`, then remove it. Put the table in `PROGRESS.md`.
2. Targets (real people, then D2's slight off-ness):
   - wrist at about 0.48 × height;
   - fingertips at about 0.38 × height (mid-thigh);
   - hand length about 0.11 × height;
   - palm width about 0.05 × height.
   Allow ±10 %. Kids' arms may stay "a touch short" (STYLE §2.2).
3. Fix through data only: `bone_scales` on each `FamilyMember` in
   `godot/art/theme/default_theme.tres`:
   - `lowerarm_*`: y shortens the forearm;
   - `hand_*`: uniform, to shrink the palm.
   Bone scale is inherited by children in Godot, so a lowerarm scale also scales the hand: compute
   the hand factor after the forearm's. Keep non-uniform scale off bones that have rotated children,
   or the hand shears. Mom already has `lowerarm 0.9` / `hand 0.92` in x and z; re-measure her as
   well.
4. Check the carry. The bundle is drawn at `FigureAnimator.hands_point()`
   (`game/art/figure_animator.gd`), so it follows the hands. There is no anim test suite; the
   numbers are these: for each member, held in `carry_idle`, `hands_point().y` minus the crown
   height must be > 0 (bundle above the head), and the distance between the two hands must be at
   least the bundle's width. Use a temporary print, then remove it. Also print the before and after
   values.
5. Frames at the end (see Done means). Fix what they show, with one redo at most.

**Already decided**
- Data change only, in `default_theme.tres`. No re-bake of the gltf bodies and no edits to the
  rig.
- The shared `figure_bone_scales` (head, neck, spine) stay as they are.
- Log the per-member hand and forearm scales and the targets above in `DECISIONS.md` as
  **REVIEW**, and update the STYLE §2.2 table's notes (Mom "hands a touch large" goes if they are no
  longer large).

**Files likely touched**
`godot/art/theme/default_theme.tres`, `STYLE.md`, `DECISIONS.md`, `PROGRESS.md`, `PLAN.md`.
Read only: `godot/game/art/art_theme.gd` (`shape_figure`), `godot/game/art/figure_animator.gd`.

**Done means**
- The measured table, before and after, in `PROGRESS.md`. Every member's after-values are within
  the targets' ±10 %, or the reason they are not is written down (kids' short arms).
- The carry check holds for all six members.
- **Frames: one capture set at the end**, opened with the Read tool, and `PROGRESS.md` says what
  each one actually shows:
  - (a) `node autobuild/family_lineup.mjs --import`: the six members, front, side and back. Hands
    end at about mid-thigh, palms no wider than the wrist-to-elbow section, and no arm looks longer
    than its body warrants.
  - (b) one close shot of dad carrying, for example
    `godot --path godot -- --capture-figure=2700,300,1000,180,dad,,carry_idle@0.5`, or the
    `--pilot=carry` + `--capture-follow=on:grab:me,...` route in `godot/CLAUDE.md` if the bundle has
    to be in the shot. The bundle is held over the head with both hands touching it, and the hands
    look normal against the head.
  - **One redo at most.**
- The full `node autobuild/verify.mjs`, run ONCE at the end, just before committing: healthy (the
  render counters within limits).

**Do NOT**
- Change collision, the sim body, `actor_height` or the drawn heights.
- Re-rig or re-bake the bodies (`rerig_family.mjs`, `figure_bake.mjs`).
- Touch the animation clips or the IK code unless the carry check fails after the data change.
- Run turnaround or anim sheets for every clip, or sweeps. The capture set above is the only one.
- Copy another game's character proportions or designs.
