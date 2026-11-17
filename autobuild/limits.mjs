// Usage-limit detection and reset-time parsing for loop.mjs.
// Kept in its own file so it can be tested without starting the loop.
//
//   isLimitMessage(output)   true when the end of a session's output is a usage/rate-limit message
//   parseReset(text, now)    the reset instant named in the text ("resets 1:50pm (America/New_York)",
//                            "resets Thu 9pm", "resets Nov 14, 9am", "resets in 2h"), or null
//   planLimitWait({...})     when to wake up: 5 min after the stated reset, or a fallback wait
//   isConnectionProblem(out) true when a failed session ended on a sign-in or network error
//   isModelLimit(out, model) true when the limit message is for that model only ("Fable limit")
//   limitAction(out, {role, model}) wait, or switch the workers to sonnet, or skip the planner

const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const DAYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];
const MONTHS = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
const DAY_RE = "(?:mon|tue|wed|thu|fri|sat|sun)[a-z]*\\.?";
const MONTH_RE = "(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.?";

// "resets" only counts when a time follows it, so "the round timer resets 3 times" is not a limit.
const RESETS_WITH_TIME =
  `\\bresets\\s+(?:in\\s+\\d|(?:on\\s+)?${DAY_RE}|${MONTH_RE}\\s+\\d|(?:at\\s+)?\\d{1,2}(?::\\d{2})?\\s*(?:am|pm)\\b|(?:at\\s+)?\\d{1,2}:\\d{2})`;

// "Fable 5.2 requires usage credits. Switch to another model, or manage usage credits at ..." is not
// a wait-for-reset limit: that model is closed to this account until credits are bought, so the loop
// treats it as a limit of that one model and moves to another model at once.
const CREDITS_RE_SRC = "\\brequires?\\s+(?:extra\\s+)?usage credits";

export const LIMIT_RE = new RegExp(
  [
    "hit your\\b[^\\n]*\\blimit",
    "\\b\\d+[- ]hour limit",
    "\\bweekly limit",
    "\\busage limit",
    "\\brate limit",
    "limit reached",
    "limit will reset",
    RESETS_WITH_TIME,
    "too many requests",
    "\\boverloaded",
    "\\b(?:error|status|code|http)\\b[^\\n]{0,20}\\b(?:429|529)\\b",
    "\\bquota\\b",
    CREDITS_RE_SRC, // "Fable 5.2 requires usage credits": a model that needs paid credits
  ].join("|"),
  "i",
);

// Only the end of the output is checked: a limit message is the last thing a blocked session prints,
// and a working session's long summary should not be mistaken for one.
export function isLimitMessage(output, tailLines = 10) {
  const lines = String(output).split(/\r?\n/).filter((l) => l.trim() !== "");
  return LIMIT_RE.test(lines.slice(-tailLines).join("\n"));
}

// Sign-in and network failures (e.g. "Failed to authenticate. API Error: 403 Attention Required! |
// Cloudflare"). These clear up on their own or after /login, so the loop waits and retries instead of
// counting them as "no progress". Checked only on a failed session's last lines, like limits, so a
// session that worked on the game's network code is not mistaken for one.
export const CONNECTION_RE =
  /Failed to authenticate|\b403\b|Cloudflare|ECONNRESET|ECONNREFUSED|ENOTFOUND|EAI_AGAIN|ETIMEDOUT|socket hang up|\bnetwork\b|API Error:?\s*5\d\d/i;

export function isConnectionProblem(output, tailLines = 10) {
  const lines = String(output).split(/\r?\n/).filter((l) => l.trim() !== "");
  return CONNECTION_RE.test(lines.slice(-tailLines).join("\n"));
}

// Waits for the 1st, 2nd, 3rd... connection problem in a row: 15, 30, 60, then 60 min each time.
export const CONNECTION_WAITS_MIN = [15, 30, 60, 60];
export const MAX_CONNECTION_WAITS = 6; // 15+30+60+60+60+60 min, about 4.75 h

export function connectionWaitMin(waitsSoFar) {
  return CONNECTION_WAITS_MIN[Math.min(waitsSoFar, CONNECTION_WAITS_MIN.length - 1)];
}

// A usage limit for one model only (e.g. "You've hit your Fable limit · resets 3pm"), when the loop
// runs with CLAUDE_MODEL. True only if the end of the output is a limit message AND it names that
// model, by the value given or by its family word (fable/opus/sonnet/haiku). A general limit
// ("You've hit your 5-hour limit") names no model and keeps the normal wait.
const FAMILY_RE = /fable|opus|sonnet|haiku/i;
export function modelFamily(model) {
  const m = String(model ?? "").match(FAMILY_RE);
  return m ? m[0][0].toUpperCase() + m[0].slice(1).toLowerCase() : String(model ?? "");
}
// True when the end of the output says a model "requires usage credits".
export function isCreditsMessage(output, tailLines = 10) {
  const lines = String(output).split(/\r?\n/).filter((l) => l.trim() !== "");
  return new RegExp(CREDITS_RE_SRC, "i").test(lines.slice(-tailLines).join("\n"));
}

export function isModelLimit(output, model, tailLines = 10) {
  if (!model || !isLimitMessage(output, tailLines)) return false;
  const tail = String(output).split(/\r?\n/).filter((l) => l.trim() !== "").slice(-tailLines).join("\n");
  // A credits message is always about one model. If its own line names a model family, that has to
  // be ours; if it names none, it is about the model we asked for.
  const creditsLine = tail.split("\n").find((l) => new RegExp(CREDITS_RE_SRC, "i").test(l));
  if (creditsLine !== undefined) {
    const named = creditsLine.match(FAMILY_RE)?.[0];
    return !named || modelFamily(named) === modelFamily(model);
  }
  const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const names = [String(model).trim(), modelFamily(model)].filter(Boolean).map(esc);
  return new RegExp(`(?<![a-z0-9])(?:${names.join("|")})(?![a-z0-9])`, "i").test(tail);
}

// What to do when a planner or worker session ended on a usage-limit message with no new commits.
//   worker, limit names its own model  -> switch the workers to `fallback` (default "sonnet") for the
//                                         rest of the run; no wait. If the worker is already on the
//                                         fallback there is nothing to switch to, so it waits.
//   planner, limit names its own model -> skip planning for the rest of the run
//   any other limit (5-hour, weekly)   -> wait for the reset, as before
//   `why` is the words for the log: "limit reached", or "requires usage credits".
export function limitAction(output, { role, model, fallback = "sonnet" }) {
  if (!isLimitMessage(output)) return { kind: "none" };
  if (!isModelLimit(output, model)) return { kind: "wait" };
  const family = modelFamily(model);
  const why = whyModelLimit(output);
  if (role === "planner") return { kind: "skip-planner", family, why };
  if (modelFamily(fallback) === family) return { kind: "wait" };
  return { kind: "switch-worker", family, to: fallback, why };
}

export function whyModelLimit(output) {
  return isCreditsMessage(output) ? "requires usage credits" : "limit reached";
}

// Which model to use after a task's "(worker: X)" tag model hit its own limit or needs credits: the
// loop's WORKER_MODEL (null = the default model). If WORKER_MODEL is itself the model that just
// failed there is nothing to fall back to, so use `fallback` ("sonnet") instead of trying it again.
export function taggedFallback({ tag, workerModel = null, fallback = "sonnet" }) {
  if (workerModel && modelFamily(workerModel) === modelFamily(tag)) return fallback;
  return workerModel;
}

function validZone(tz) {
  if (!tz) return undefined;
  try { new Intl.DateTimeFormat("en-US", { timeZone: tz }); return tz; } catch { return undefined; }
}

// Wall-clock parts of an instant in a time zone (undefined = this PC's zone).
function wallParts(ms, tz) {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: tz, hourCycle: "h23", year: "numeric", month: "numeric", day: "numeric",
    hour: "numeric", minute: "numeric", second: "numeric",
  });
  const p = Object.fromEntries(f.formatToParts(new Date(ms)).map((x) => [x.type, x.value]));
  return { y: +p.year, mo: +p.month - 1, d: +p.day, h: +p.hour % 24, mi: +p.minute, s: +p.second };
}

function offsetMs(ms, tz) {
  const w = wallParts(ms, tz);
  return Date.UTC(w.y, w.mo, w.d, w.h, w.mi, w.s) - Math.floor(ms / 1000) * 1000;
}

// A wall-clock time in a zone -> the real instant (handles daylight-saving changes).
function wallToInstant(y, mo, d, h, mi, tz) {
  const guess = Date.UTC(y, mo, d, h, mi);
  let t = guess - offsetMs(guess, tz);
  t = guess - offsetMs(t, tz);
  return t;
}

export function parseReset(text, now = Date.now()) {
  const s = String(text);

  // "resets in 2h", "resets in 45 minutes", "resets in 1 hour 30 min"
  const rel = s.match(/\bresets?\s+in\s+(\d+)\s*(h|hrs?|hours?|m|mins?|minutes?)\b(?:\s*(\d+)\s*(?:m|mins?|minutes?)\b)?/i);
  if (rel) {
    const n = Number(rel[1]);
    const ms = /^h/i.test(rel[2]) ? n * HOUR + Number(rel[3] ?? 0) * MIN : n * MIN;
    return { at: now + ms, text: rel[0], zone: "relative", hasDay: false };
  }

  const re = new RegExp(
    `\\bresets?\\s+(?:on\\s+)?(?:(${DAY_RE}),?\\s+)?(?:(${MONTH_RE})\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+)?` +
      `(?:at\\s+)?(\\d{1,2})(?::(\\d{2}))?\\s*(am|pm)?(?:\\s*\\(([^)]+)\\))?`,
    "i",
  );
  const m = s.match(re);
  if (!m) return null;
  const [whole, dayWord, monthWord, dateNum, hourStr, minStr, ampm, zoneStr] = m;
  if (!ampm && minStr === undefined) return null; // "resets 5" alone is not a time
  let hour = Number(hourStr);
  const minute = Number(minStr ?? 0);
  if (ampm) {
    if (hour < 1 || hour > 12) return null;
    hour = (hour % 12) + (/pm/i.test(ampm) ? 12 : 0);
  } else if (hour > 23) return null;
  if (minute > 59) return null;

  const zone = validZone(zoneStr?.trim());
  const today = wallParts(now, zone);
  const earliest = now - 2 * MIN; // a reset that is "just now" still counts
  let at = null;

  if (monthWord) {
    const mo = MONTHS.indexOf(monthWord.slice(0, 3).toLowerCase());
    for (const y of [today.y, today.y + 1]) {
      const t = wallToInstant(y, mo, Number(dateNum), hour, minute, zone);
      if (t > earliest) { at = t; break; }
    }
  } else {
    const wantDay = dayWord ? DAYS.indexOf(dayWord.slice(0, 3).toLowerCase()) : -1;
    for (let k = 0; k <= 8 && at === null; k++) {
      const cal = new Date(Date.UTC(today.y, today.mo, today.d + k));
      if (wantDay >= 0 && cal.getUTCDay() !== wantDay) continue;
      const t = wallToInstant(cal.getUTCFullYear(), cal.getUTCMonth(), cal.getUTCDate(), hour, minute, zone);
      if (t > earliest) at = t;
    }
  }
  if (at === null || at - now > 8 * DAY) return null;
  return {
    at,
    text: whole.trim(),
    zone: zone ?? (zoneStr ? `this PC's time zone ("${zoneStr}" not recognised)` : "this PC's time zone"),
    hasDay: Boolean(dayWord || monthWord),
  };
}

// lastTarget: the reset time the loop last waited for. If the same daily time comes back after it
// has passed, the limit did not lift as stated, so use the fallback ladder instead of waiting a day.
export function planLimitWait({ text, now = Date.now(), lastTarget = null, step = 1, backoffMin = 30, graceMin = 5 }) {
  const r = parseReset(text, now);
  const repeat = r !== null && lastTarget !== null && now >= lastTarget && !r.hasDay &&
    Math.abs(r.at - lastTarget - DAY) < 2 * HOUR;
  if (r && !repeat) {
    return { until: Math.max(r.at + graceMin * MIN, now + MIN), target: r.at, source: `"${r.text}", read in ${r.zone}` };
  }
  const mins = Math.min(backoffMin * 2 ** (step - 1), 180);
  return {
    until: now + mins * MIN,
    target: null,
    source: repeat ? `still limited after the stated reset; fallback wait ${mins} min` : `no reset time found; fallback wait ${mins} min`,
  };
}
