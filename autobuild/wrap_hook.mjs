// Claude Code hook (PostToolUse, see .claude/settings.json). While the loop has asked sessions to wrap up
// because the 5-hour limit is nearly used, autobuild/WRAP_UP exists; this prints its text into the
// session after every tool call, so the session commits and finishes. With no WRAP_UP file it prints
// nothing, so normal sessions and interactive use are untouched.
// Must never fail loudly: any problem means "print nothing".
import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

try {
  const file = join(dirname(fileURLToPath(import.meta.url)), "WRAP_UP");
  if (existsSync(file)) {
    const text = readFileSync(file, "utf8").trim();
    if (text) process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: text } }));
  }
} catch { /* print nothing */ }
