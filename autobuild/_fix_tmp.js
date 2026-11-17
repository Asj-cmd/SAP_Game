const fs = require('fs');
const g = fs.readFileSync('PROGRESS.md', 'utf8');
const lines = g.split(/\r?\n/);
const i = lines.findIndex(l => l.startsWith('## 2026-11-17 — P4-8'));
const j = lines.findIndex((l, k) => k > i && l.startsWith('## '));
const entry = `## 2026-11-17 — P4-8 Panic run is animation only; defenders are faster at home
- **Followed the brief.** \`panic_speed_scale\` deleted; \`home_speed_scale\` 1.08 added to \`TuningDef\`; \`MovementSystem._speed_for\` multiplies by it when \`zone_at(position)\` is owned by the actor's team (carrier at home 0.85 x 1.08, crouch 0.55 x 1.08; REVIEW). \`FigureAnimator.base_clip\` / \`update\` take \`panicking\` (from \`MovementSystem.is_panicking\` on the world the motion came from, in \`GreyBoxMain._animate\`); \`PANIC_FRACTION\` deleted. Count and snapshot unchanged. D9 rewritten, two log rows.
- **Tests:** panic rows now expect no speed change; new \`_test_home_speed\` (7 rows: own, other family's, unowned, no team, carrier, crouched, panicking at home). movement_system_test 149 -> 156, pinned.
- **Hedge REDO** (\`ExteriorBuilder._hedge\`, 3 call sites): dark base band 60 high, leafy sides in two tones (lower textured, upper lighter plain), 40 chamfer strips and a yellower flat top. First try: only the base band showed at eye level (the top is not visible from there) and the slab was still uniform. The one redo added the lighter upper band. Now \`approach_from_south\` and \`ext_a_west\` show a dark base, a textured mid and a lighter flat band above: tonal bands rather than one slab, but still a flat-faced wall with box edges; the chamfer and top are not seen from these cameras. Verdict: better, not a convincing hedge. approach_from_south 204,622 triangles (limit 257,000).
- **Panic sheet** \`autobuild/frames/p4_8/panic_sheet.png\` (own body, W+D held): printed speed 583 in every moving cell; cells 2-5 \`jog\`, from cell 6 (about 2 s after the key) \`panic_run\`, speed still 583 (no boost; 648 in P4-1). From cell 6 the body has one arm straight overhead and one reaching forward-up, long stride, running along House A's side wall on its own lawn. Cells 2-3 press into the wall as in P4-1. Cell 16 idle.
- **Verify:** see below.
- **Left:** hedges still blocky. P4-6 should have nothing to do (bots never used the boost): tick it if verify is healthy.
`;
lines.splice(i, j - i, ...entry.split('\n'));
fs.writeFileSync('PROGRESS.md', lines.join('\n'));
