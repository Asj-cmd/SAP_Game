// Planner/worker helpers for loop.mjs, kept apart so they can be tested without starting the loop.
//
//   firstOpenTaskId(planText)   id of the first open task ("P3-4"): the first line that is `[ ]` or `[~]`.
//                               `[x]` done, `[-]` deferred and `[B]` blocked are never open.
//   briefHeadings(briefText)    task ids that have a section in BRIEF.md (a "## P3-4 ..." heading)
//   hasBriefFor(briefText, id)  true when BRIEF.md has a section for that task

const TASK_LINE = /^- \[[ ~]\] \*\*(P\d+-\d+[a-z]*)\b/m;

export function firstOpenTaskId(planText) {
  return String(planText).match(TASK_LINE)?.[1] ?? null;
}

export function briefHeadings(briefText) {
  return [...String(briefText).matchAll(/^##\s+(P\d+-\d+[a-z]*)\b/gm)].map((m) => m[1]);
}

export function hasBriefFor(briefText, id) {
  return id !== null && briefHeadings(briefText).includes(id);
}
