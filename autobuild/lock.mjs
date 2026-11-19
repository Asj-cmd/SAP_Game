// The loop's lock file (autobuild/loop.lock holds the loop's PID). A lock whose PID is no longer running is stale.
//   node autobuild/lock.mjs --check   exit code 0 = a live loop holds the lock, 1 = no live lock
import { existsSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

export const lockPath = (autobuildDir) => join(autobuildDir, "loop.lock");

export function pidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; } catch (e) { return e.code === "EPERM"; }
}
export function readLock(file) {
  try { const pid = parseInt(readFileSync(file, "utf8").trim(), 10); return Number.isInteger(pid) ? pid : null; } catch { return null; }
}
export const liveLock = (file) => pidAlive(readLock(file));
export const writeLock = (file, pid = process.pid) => writeFileSync(file, String(pid) + "\n");
// Removes the lock only if it is ours (never another loop's).
export function removeOwnLock(file, pid = process.pid) { try { if (existsSync(file) && readLock(file) === pid) unlinkSync(file); } catch { /* ignore */ } }

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1] && process.argv.includes("--check")) {
  process.exit(liveLock(lockPath(dirname(fileURLToPath(import.meta.url)))) ? 0 : 1);
}
