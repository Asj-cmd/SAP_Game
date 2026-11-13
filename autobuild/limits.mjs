// Usage-limit detection and reset-time parsing for loop.mjs.
// Kept in its own file so it can be tested without starting the loop.
//
//   isLimitMessage(output)   true when the end of a session's output is a usage/rate-limit message
//   parseReset(text, now)    the reset instant named in the text ("resets 1:50pm (America/New_York)",
//                            "resets Thu 9pm", "resets Nov 14, 9am", "resets in 2h"), or null
//   planLimitWait({...})     when to wake up: 5 min after the stated reset, or a fallback wait

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
  ].join("|"),
  "i",
);

// Only the end of the output is checked: a limit message is the last thing a blocked session prints,
// and a working session's long summary should not be mistaken for one.
export function isLimitMessage(output, tailLines = 10) {
  const lines = String(output).split(/\r?\n/).filter((l) => l.trim() !== "");
  return LIMIT_RE.test(lines.slice(-tailLines).join("\n"));
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
