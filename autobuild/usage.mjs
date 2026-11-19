// Usage guard for loop.mjs: read how much of the 5-hour (and weekly) limit is used, from the
// "rate_limit_event" lines that `claude -p --output-format stream-json --verbose` prints, and decide
// when the loop must stop starting work, ask the session to wrap up, or cut it off.
//
// The numbers: utilization 0..1 per window (five_hour, seven_day), resetsAt in epoch SECONDS.
//
// The rule (set by the user, 2026-11-19): leave 20 % of the 5-hour limit for the user.
//   - at 75 % (USAGE_STOP_PCT): start no new session; a running one is asked to commit and finish
//   - by 80 % (USAGE_HARD_PCT), or after WRAP_UP_MIN minutes, a session that has not finished is cut
//     off and the loop saves its leftovers itself (commit + push)
//   - then the loop waits for the 5-hour reset (+ a few minutes) and carries on by itself
// The weekly limit has no early stop: when it is really hit, loop.mjs waits for its reset and restarts.
//
//   readingFromEvent(ev)            { five_hour, seven_day } windows from one rate_limit_event, or null
//   UsageTracker                    keeps the newest reading per window; fiveHour(now) / sevenDay(now)
//   textFromStream(stdout)          the plain text of a stream-json run (assistant text, result text)
//   eventsFromChunk(buffer, chunk)  split a stdout chunk into complete JSON lines
//   preflight(tracker, opts)        { wait: false } or { wait: true, until, pct } before a session starts
//   monitorDecision(...)            "ok" | "wrap" | "kill" while a session runs

export const MIN = 60_000;
export const RESET_SLACK_MS = Number(process.env.USAGE_RESET_SLACK_MIN ?? 3) * MIN; // wake this long after the stated reset
export const pctOf = (u) => Math.round(u * 100);

const win = (w) => (w && Number.isFinite(Number(w.utilization)) ? {
  utilization: Number(w.utilization),
  resetsAt: Number.isFinite(Number(w.resetsAt)) ? Number(w.resetsAt) : null,
  status: w.status ?? null,
} : null);

// One parsed stream-json object -> { five_hour, seven_day } (either may be null), or null if it is not a
// rate_limit_event. Uses unifiedWindows when present, else the top-level window named by rateLimitType.
export function readingFromEvent(ev) {
  if (!ev || ev.type !== "rate_limit_event" || !ev.rate_limit_info) return null;
  const info = ev.rate_limit_info;
  const out = { five_hour: null, seven_day: null };
  const uw = info.unifiedWindows;
  if (uw && typeof uw === "object") { out.five_hour = win(uw.five_hour); out.seven_day = win(uw.seven_day); }
  if (!out.five_hour && info.rateLimitType === "five_hour") out.five_hour = win(info);
  if (!out.seven_day && /^seven_day/.test(info.rateLimitType ?? "")) out.seven_day = win(info);
  return out.five_hour || out.seven_day ? out : null;
}

export class UsageTracker {
  constructor() { this.five = null; this.seven = null; }
  update(reading) {
    if (!reading) return false;
    if (reading.five_hour) this.five = reading.five_hour;
    if (reading.seven_day) this.seven = reading.seven_day;
    return true;
  }
  clear(which = "both") { if (which !== "seven") this.five = null; if (which !== "five") this.seven = null; }
  // A reading is only good until its window resets: after that the usage is 0 as far as we know.
  fiveHour(now = Date.now()) { return fresh(this.five, now); }
  sevenDay(now = Date.now()) { return fresh(this.seven, now); }
  summary(now = Date.now()) {
    const f = this.fiveHour(now), s = this.sevenDay(now);
    const parts = [];
    if (f) parts.push(`5-hour ${pctOf(f.utilization)}%`);
    if (s) parts.push(`weekly ${pctOf(s.utilization)}%`);
    return parts.length ? parts.join(", ") : null;
  }
}
const fresh = (w, now) => (w && (w.resetsAt === null || w.resetsAt * 1000 > now) ? w : null);

// Complete JSON lines from a growing stdout. `state.rest` carries the unfinished last line.
export function eventsFromChunk(state, chunk) {
  state.rest = (state.rest ?? "") + chunk;
  const lines = state.rest.split("\n");
  state.rest = lines.pop();
  const events = [];
  for (const l of lines) {
    const t = l.trim();
    if (!t.startsWith("{")) continue;
    try { events.push(JSON.parse(t)); } catch { /* not JSON: ignore */ }
  }
  return events;
}

// What `--output-format text` would have shown, rebuilt from the stream: every assistant text block and
// every result string, one per line, plus any error text. The loop's limit / sign-in checks read this.
export function textFromStream(stdout) {
  const parts = [];
  const add = (s) => { if (typeof s === "string" && s.trim()) parts.push(s.trim()); };
  for (const line of String(stdout).split("\n")) {
    const t = line.trim();
    if (!t.startsWith("{")) { if (t) parts.push(t); continue; } // plain lines (e.g. an error before the stream)
    let ev; try { ev = JSON.parse(t); } catch { parts.push(t); continue; }
    if (ev.type === "assistant" && Array.isArray(ev.message?.content)) {
      for (const b of ev.message.content) if (b?.type === "text") add(b.text);
    } else if (ev.type === "result") {
      add(ev.result); if (Array.isArray(ev.errors)) ev.errors.forEach(add);
    } else if (ev.type === "system" && ev.subtype === "api_retry") {
      add(`API Error: ${ev.error_status ?? ""} ${ev.error ?? ""}`);
    } else if (ev.type === "error") {
      add(ev.message ?? ev.error);
    }
  }
  return parts.join("\n");
}

// Before starting a session: is the 5-hour window already at or over the stop line?
export function preflight(tracker, { stopPct = 75, now = Date.now() } = {}) {
  const f = tracker.fiveHour(now);
  if (!f || f.utilization * 100 < stopPct) return { wait: false };
  const until = f.resetsAt ? f.resetsAt * 1000 + RESET_SLACK_MS : now + 30 * MIN;
  return { wait: true, until, pct: pctOf(f.utilization) };
}

// While a session runs. wrapSince = ms when the wrap-up request was made (null before).
export function monitorDecision(tracker, { stopPct = 75, hardPct = 80, wrapMin = 15, wrapSince = null, now = Date.now() } = {}) {
  const f = tracker.fiveHour(now);
  const pct = f ? f.utilization * 100 : 0;
  if (wrapSince !== null) {
    if (pct >= hardPct) return { action: "kill", why: `5-hour usage reached ${pctOf(f.utilization)}% (hard stop ${hardPct}%)` };
    if (now - wrapSince >= wrapMin * MIN) return { action: "kill", why: `did not finish ${wrapMin} min after the wrap-up request` };
    return { action: "ok" };
  }
  if (f && pct >= stopPct) return { action: "wrap", why: `5-hour usage reached ${pctOf(f.utilization)}% (stop at ${stopPct}%)` };
  return { action: "ok" };
}

// When a window is really full (status "rejected" or 99.5 %+), the exact reset instant in ms: the later
// of the full windows. null when no event says so.
export function usageResetAt(tracker, now = Date.now()) {
  const full = [tracker.five, tracker.seven].filter((w) => w && w.resetsAt && w.resetsAt * 1000 > now && (w.status === "rejected" || w.utilization >= 0.995));
  return full.length ? Math.max(...full.map((w) => w.resetsAt * 1000)) : null;
}
