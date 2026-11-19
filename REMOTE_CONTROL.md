# Running the loop while you are away

Two helpers: **start-loop.cmd** starts the loop in its own window, and a **watchdog** (run by Windows every
30 minutes) restarts it if it has crashed. Neither runs Claude by itself.

## 1. Keep the laptop awake
1. Plug the laptop into the charger and leave it plugged in.
2. Start menu > **Settings** > **System** > **Power & battery** (older Windows: **Power & sleep**).
3. Under **Screen and sleep**, set **When plugged in, put my device to sleep after** to **Never**.
   (The screen may still turn off; that is fine.)

## 2. Task Scheduler: the watchdog (once)
1. Start menu, type **Task Scheduler**, open it.
2. Right-hand panel: **Create Task...** (not "Create Basic Task").
3. **General** tab: Name `CashGrab watchdog`. Choose **Run only when user is logged on**
   (the loop window needs your desktop).
4. **Triggers** tab > **New...** > Begin the task: **On a schedule**, **Daily**, start today. Tick
   **Repeat task every** and choose **30 minutes** (type it in if it is not listed), **for a duration of**
   **1 day**. Make sure **Enabled** is ticked > **OK**.
5. **Actions** tab > **New...** > Action **Start a program**.
   Program/script: `node`
   Add arguments: `autobuild\watchdog.mjs`
   Start in: `C:\Users\Jampa\cashgrab-auto` > **OK**.
6. **Conditions** tab: if the laptop may run on battery, **untick** "Start the task only if the computer is on AC power".
7. **OK**. If it asks for your Windows password, type it.
8. Test: right-click the task > **Run**. Then open `autobuild\watchdog.log`: one new line says START or skip, with the reason.

## 3. Remote access: Chrome Remote Desktop (once)
1. On this laptop, open Chrome, go to **remotedesktop.google.com/access**, sign in with your Google account.
2. Under **Set up remote access** click the download arrow, install, name the laptop, and choose a **PIN** (6+ digits).
3. On your phone (Chrome Remote Desktop app) or another computer, sign in with the **same Google account**.
   The laptop appears in the list.

## 4. Starting and stopping from away
- **Start:** open Chrome Remote Desktop, tap the laptop, enter the PIN. Double-click **start-loop.cmd** in the
  `cashgrab-auto` folder. A window titled "CashGrab loop" opens. If a loop is already running it just prints
  "Loop already running".
- **Stop:** in the `cashgrab-auto` folder create an empty file named exactly **STOP** (right-click > New >
  Text Document, name it `STOP`, remove the `.txt` ending; you may need View > File name extensions). The loop
  finishes the current session, commits, and ends. It also ends a usage-limit wait within 5 minutes. The
  watchdog will not restart it while STOP exists.
- **Start again after a STOP:** delete the STOP file. Then double-click start-loop.cmd (the watchdog will not
  do it for you, because the last status says "stopped: STOP file").

## 5. What to expect
- The watchdog restarts a **crashed** loop (closed window, reboot, power cut) within 30 minutes, as long as
  there is no STOP file and PLAN.md still has an open task.
- A **Claude usage-limit wait is not a crash**: the loop is still running, holds its lock, and resumes by
  itself after the reset (the 75% / 80% guard works the same way).
- It does **not** restart a loop that ended because the plan is finished, or after a STOP.
- A loop that stops on an error (for example Claude is signed out) will be restarted every 30 minutes and
  stop again. If STATUS.md keeps saying "stopped: error ...", fix the cause (run `claude`, `/login`) or create STOP.
- **If the watchdog says "stopped: repeated crash, check the terminal"** (in `autobuild\STATUS.md` and `autobuild\watchdog.log`), it restarted the loop 3 times in a row and each time the loop was gone within 10 minutes, so it gave up and does nothing more. Open the loop's terminal over Chrome Remote Desktop, read the error, fix it (usually a Claude sign-in: run `claude`, type `/login`), then run start-loop.cmd. Running it by hand resets the count.
- Look at `autobuild\STATUS.md` (also on GitHub) for what it is doing, and `autobuild\watchdog.log` for what the watchdog did.
