// Planner/worker helpers for loop.mjs, kept apart so they can be tested without starting the loop.
//
//   firstOpenTaskId(planText)   id of the first open task ("P3-4"): the first line that is `[ ]` or `[~]`.
//                               `[x]` done, `[-]` deferred and `[B]` blocked are never open.
//   pickWorkerModel(plan, ...)  the model for the next worker: a "(worker: fable)" tag on the first open
//                               task's line, else WORKER_MODEL
//   briefHeadings(briefText)    task ids that have a section in BRIEF.md (a "## P3-4 ..." heading)
//   hasBriefFor(briefText, id)  true when BRIEF.md has a section for that task

const TASK_LINE = /^- \[[ ~]\] \*\*(PT?\d+-\d+[a-z]*)\b/m;

export function firstOpenTaskId(planText) {
  return String(planText).match(TASK_LINE)?.[1] ?? null;
}

// The first open task's own line in PLAN.md (the `- [ ] **P2-6 ...` line, not its indented text).
export function firstOpenTaskLine(planText) {
  return String(planText).split(/\r?\n/).find((l) => /^- \[[ ~]\] /.test(l)) ?? null;
}

// "(worker: fable)" on a task's line names the model for that task's worker session.
export function taggedWorker(line) {
  const m = String(line ?? "").match(/\(worker:\s*([A-Za-z0-9._-]+)\)/i);
  return m ? m[1].toLowerCase() : null;
}

// Which model the next worker session uses: the first open task's tag, unless that tag has been
// switched off for this run (its own limit was hit), else the loop's WORKER_MODEL (null = default).
//   tagOff: Set of tag values that hit their own limit.
export function pickWorkerModel(planText, { workerModel = null, tagOff = new Set() } = {}) {
  const tag = taggedWorker(firstOpenTaskLine(planText));
  if (tag && !tagOff.has(tag)) return { model: tag, tagged: true };
  return { model: workerModel, tagged: false };
}

export function briefHeadings(briefText) {
  return [...String(briefText).matchAll(/^##\s+(PT?\d+-\d+[a-z]*)\b/gm)].map((m) => m[1]);
}

export function hasBriefFor(briefText, id) {
  return id !== null && briefHeadings(briefText).includes(id);
}
