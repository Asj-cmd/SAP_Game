# Running the autonomous build on your Windows PC

## One-time setup (about 15 minutes)

1. **Godot 4.7 (standard, not .NET).** Download from godotengine.org, unzip somewhere permanent,
   e.g. `C:\Godot\`. Use the file named `…_win64_console.exe` (prints to the terminal).
2. **Git for Windows**, **Node.js** (you already have it for the old build) and **Claude Code**,
   signed in (`claude` once in a terminal, finish the login).
3. **A fresh, separate copy of the repo** (never your working copy):
   ```
   cd C:\Users\Jampa
   git clone https://github.com/Asj-cmd/SAP_Game.git cashgrab-auto
   cd cashgrab-auto
   git checkout claude/godot-port
   git checkout -b claude/autobuild
   ```
4. **Unzip `autobuild-kit.zip` into that folder** (overwrite when asked: it replaces `godot/CLAUDE.md`
   with the same file plus an "Autonomous mode" section). Then:
   ```
   mkdir .claude
   copy autobuild\settings.proposed.json .claude\settings.json
   git add -A
   git commit -m "Add autobuild system"
   git push -u origin claude/autobuild
   ```
   (Look at `settings.proposed.json` first: it is the list of things Claude may do unattended.)
5. **Tell the loop where Godot is** (PowerShell, every new window):
   ```
   $env:GODOT_BIN = "C:\Godot\Godot_v4.7-stable_win64_console.exe"
   ```
6. *Optional, helps a lot:* put 3–5 screenshots of games whose look you like in
   `autobuild\references\` (Meccha Chameleon, etc.). The style tasks read them.
7. *Optional:* sign in to Meshy once if you want AI-generated characters; otherwise the loop
   uses free character packs.

## Check that it works (10 minutes, stay and watch)

```
node autobuild/verify.mjs --frames     # tests + bot match + screenshots; ends "VERIFY: healthy"
node autobuild/loop.mjs --max-iters 1  # one real session on the first task, then stop
```
Read `autobuild\REPORT.md` and the newest file in `autobuild\logs\`. Only start the all-day run
after this works.

## All-day run

Windows, once per day:
- Settings → System → Power: **Sleep: Never** (plugged in). Laptop: *Choose what closing the lid does* → **Do nothing**.
  Command line: `powercfg /change standby-timeout-ac 0` and `powercfg /change hibernate-timeout-ac 0`.
- Keep the **screen on** (turn brightness down) for the first run; Godot screenshots can fail on a locked screen.
  Turn off the lock screen / screen saver sign-in requirement.
- **Pause Windows Update** for a week (Settings → Windows Update → Pause), so it cannot reboot.
- Plugged in, on a hard surface (the GPU runs hot), other heavy programs closed. Don't use the PC while it runs.

Start it:
```
$env:GODOT_BIN = "C:\Godot\Godot_v4.7-stable_win64_console.exe"
node autobuild/loop.mjs
```
Stop it at any time by creating an empty file called `STOP` in the folder (it finishes the current session first).

What it does on its own: runs one task per fresh Claude session, commits, pushes the branch to GitHub,
waits and retries when you hit a usage limit, and gives up after 3 sessions in a row with no
commits so it cannot burn your weekly limit going nowhere. `--skip-permissions` removes all
permission checks; only use it in this throwaway copy, with no secrets in it.

## In the evening (10 minutes)

1. `autobuild\REPORT.md`: what was done, what is open, what needs you.
2. `BLOCKED.md`: things only you can do (accounts, money, installs). Do them or tell me to skip.
3. `DECISIONS.md`: rows marked `REVIEW` (style, characters, team colours). Reply with changes.
4. `autobuild\frames\` and `autobuild\slice\`: look at the pictures. This is where your taste matters.
5. Run the game yourself: `godot --path godot` from the folder, or open `godot\project.godot` in the editor.

## Files

| File | What it is |
|---|---|
| `PLAN.md` | The task list the loop works through |
| `DECISIONS.md` | The rules for deciding without you, and the decision log |
| `PROGRESS.md` | What each session did and what it saw |
| `BLOCKED.md` | What needs you |
| `autobuild/verify.mjs` | Tests + bot match + screenshots, with pinned counts that can only tighten |
| `autobuild/loop.mjs` | The loop |
| `autobuild/PROMPT.md` | What every session is told |
