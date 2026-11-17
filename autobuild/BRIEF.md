# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

## P6-2 — Host modes

**Approach**
1. Confirm what exists and write it down: today the only host is a **listen host**. `--host` (or menu
   Host) makes `MatchLink.host(...)` in `game/greybox/greybox_main.gd` `_start()`, then
   `link.seat_local("You")` sits the host's own player down before any guest, and the host runs the
   authoritative world plus the bot crew. `game/debug/net_smoke.gd` already runs that host
   `--headless`, so the game scene works without a window.
2. Add a short section to `godot/ARCHITECTURE.md` (in §1 Layers or after §5, "Host modes"): listen
   host (default; host plays), dedicated host (below), who owns the authoritative world, who fills
   bots, which flags start each, and that Steam (P6-3) is a transport, not a host mode.
3. Implement the dedicated host only as a thin flag, **if it stays small** (aim: under ~120 changed
   lines in `greybox_main.gd`; if it grows past that, stop, document it as not built, tick the task
   with that note):
   - `--dedicated` implies `--host` (`_role_from_command_line`, `_wants_menu` skips the menu).
   - Skip `link.seat_local(...)`: no seat for this machine, so the first guest gets the first seat.
   - Skip building seats/viewports, cameras, HUD, audio, first-run guide (guard where `_build_seats`,
     `GameAudio`, `FirstRunGuide` are made). Keep the sim tick and the link's networking exactly as on
     a listen host.
   - Print the session code once to stdout (`link.session_code()`, with `--advertise=` as today).
   - Start: wait in WAITING; begin the match `--dedicated-wait=` seconds (default 15) after the first
     guest is seated, through the existing `_begin_match()` (bots fill empty seats as usual).
     MATCH_END: rematch automatically after the results time, so the server keeps serving.
4. Update `godot/PLAYTEST.md` with the one command line for a dedicated host.

**Already decided**
- The dedicated host is the same game scene run with `--headless --dedicated`, not a separate
  project or export (log in DECISIONS.md, plain).
- Start rule = 15 s after the first guest is seated, bots fill the rest; automatic rematch at MATCH_END
  (log as REVIEW: friends may prefer a manual start).
- No new network messages, no change in `net/` or `sim/`, no snapshot format change.

**Files likely touched**
- `godot/ARCHITECTURE.md`, `godot/PLAYTEST.md`, `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`
- `godot/game/greybox/greybox_main.gd` (flags, guards, start/rematch on a dedicated host)
- maybe `godot/game/greybox/match_link.gd` (only if a "guest seated" query is missing; `lobby` is public)

**Done means**
- ARCHITECTURE.md describes both modes accurately against the code.
- If built: a headless `--dedicated` run through `node autobuild/run_game.mjs` prints the code and no
  script errors (one run, as P5-4/P5-5 did with `--solo`).
- Full `node autobuild/verify.mjs` ONCE at the end, before the commit: healthy, every suite at its
  pinned count, symmetry exact, bot match 3v3 + 1v1, tick budget, net_smoke in lockstep.

**Do NOT**
- Write a separate server binary, a headless export preset, or a matchmaking/directory service.
- Touch `sim/`, `net/` transports, the snapshot or the lobby rules.
- Add a test file or a verify gate for the dedicated host. Bot tuning, sweeps.
- Run verify at the start.

## P6-3 — Steam transport

**Approach**
1. Write `godot/net/steam_transport.gd` (`class_name SteamTransport extends SessionTransport`,
   `backend_name()` = `&"steam"`) that talks to Steam ONLY through an injected `Object`
   (`var steam: Object`, default `Engine.get_singleton("Steam")` when `Engine.has_singleton("Steam")`,
   else null). With null, `host_session()` returns an invalid handle and `failure()` says
   "Steam is not available (GodotSteam not installed or Steam not running)". The project must parse
   and run with no addon present: use `steam.call("name", ...)` / `has_method`, never the `Steam`
   class name in code.
2. Session = a Steam lobby: `host_session()` calls `createLobby` (friends-only, max = 2 × team size)
   and returns a `SessionHandle(&"steam", "<lobby id>")` once the lobby id arrives (OPENING until then);
   `join_session()` calls `joinLobby(id)`, learns the owner's Steam id, and goes READY after the
   handshake below. The 64-bit lobby id already packs into a LobbyCode (`PACK_NUMBER`, tested in
   `lobby_test.gd`).
3. Bytes = Steam Networking Messages (`sendMessageToUser`, `receiveMessagesOnChannel`, one channel).
   RELIABLE → reliable send flag (8), UNRELIABLE → unreliable (0). Poll messages inside `poll()`; also
   run `steam.call("run_callbacks")` there if the singleton does not do it itself.
4. Peer ids: the host is `HOST_PEER` (1); the host gives each Steam id the next int from 2 in join
   order, in a tiny transport-level handshake (guest → host `HELLO`, host → guest `WELCOME <id>`; one
   reserved first byte so it never reaches `MatchChannel`). PEER_JOINED/PEER_LEFT events as the ENet
   backend emits them (read `enet_transport.gd` and copy its event shapes exactly).
5. Wire `backend == "steam"` into `MatchLink._transport` (`match_link.gd:144`) and the two tools
   that pick a backend (`tools/net_loopback.gd:122`, `tools/net_lobby.gd:180`). `--backend=steam`
   already reaches `_backend` in `greybox_main.gd`.
6. Conformance without Steam: add a minimal fake Steam object (an inner class in
   `tests/transport_test.gd`: lobby create/join, a shared in-memory mailbox per Steam id) and run the
   existing per-backend rows on `SteamTransport` too. Re-pin the count in `autobuild/test_baseline.json`.
7. Add `godot/steam_appid.txt` with `480` (Spacewar, dev only), excluded from export later (note for P7-1).
8. Write the BLOCKED.md entry (below). Update ARCHITECTURE.md (the transport list) and ASSETS.md is not
   needed (no asset added).

**Already decided**
- **Do not download GodotSteam or any Steam DLL in this session.** The GDExtension bundles Valve's
  `steam_api64.dll` under the Steamworks SDK agreement, which is the user's to accept, and a build for
  Godot 4.7 may not exist yet. BLOCKED.md entry: "install GodotSteam GDExtension for Godot 4.7 into
  `godot/addons/godotsteam/`, have the Steam client running and logged in; then `--backend=steam`
  works with app id 480; the real app id needs a Steamworks partner account and the app fee (money)".
  Mark the task `[x]` with the note "live two-instance test waits on BLOCKED.md", not `[B]` (the code
  part is not blocked). Log in DECISIONS.md as REVIEW.
- Networking Messages, not `SteamMultiplayerPeer`: the game has its own `SessionTransport`, not
  Godot's high-level multiplayer (D5).
- Peer ids assigned by the host in join order; Steam ids never leave the transport except as the
  identity slot (`player_identity.gd:16` says where a Steam id goes later; leave identity unchanged
  in this task unless it is one line).

**Files likely touched**
- `godot/net/steam_transport.gd` (new)
- `godot/game/greybox/match_link.gd`, `godot/tools/net_loopback.gd`, `godot/tools/net_lobby.gd`
- `godot/tests/transport_test.gd`, `autobuild/test_baseline.json`
- `godot/steam_appid.txt` (new), `godot/ARCHITECTURE.md`, `BLOCKED.md`, `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`
- Note: a new `class_name` needs one `--import` run before tools see it (P6-1).

**Done means**
- `transport_test` runs its rows on loopback, ENet and SteamTransport-with-fake, all passing; new
  count pinned.
- `--backend=steam` with no addon fails cleanly with the message above (menu returns "Could not
  start: ...", CLI shows it in the banner), no script error.
- Full `node autobuild/verify.mjs` ONCE at the end, before the commit: healthy, net_smoke (ENet)
  unchanged and in lockstep.

**Do NOT**
- Download or commit GodotSteam, `steam_api*.dll`, or the Steamworks SDK. Do not create accounts.
- Reference the `Steam` class name directly (the project would fail to parse without the addon).
- Change `SessionTransport`'s interface, `MatchChannel` framing, the snapshot, the lobby rules or `sim/`.
- Build the invite/overlay flow (that is P6-4). Bot work, sweeps, a new test file.

## P6-4 — Invite/join flow

**Approach**
1. Keep the room-code path exactly as it is (ENet code from Host, typed into Join). Steam is an extra
   route, shown only when `SteamTransport` reports Steam available (P6-3's check).
2. Main menu (`game/greybox/main_menu.gd`): when Steam is available, a "Host on Steam" button next to
   Host (same team-size picker); it emits the existing `host_chosen` path with backend `steam` (add a
   backend argument or a second signal; keep `_on_host` for ENet untouched).
3. Lobby panel (`game/greybox/lobby_panel.gd`): on a Steam host, an "Invite friends" button calling
   `activateGameOverlayInviteDialog(lobby_id)` through the transport's Steam object, plus the code
   (the Steam lobby id packed by `LobbyCode`) so it can still be read out.
4. Joining from an invite: (a) launch argument `+connect_lobby <id>` (Steam passes it when the game is
   started from an invite) parsed in `greybox_main.gd` `_read_command_line` → role GUEST, backend
   `steam`, handle `steam:<id>`, menu skipped; (b) while running, the Steam `join_requested` signal
   (connect via `steam.connect("join_requested", ...)` if the signal exists) → `_on_join` with that
   handle. A pasted Steam code in Join already decodes to a steam handle; make `_launch` pick the
   backend from the decoded handle instead of the CLI default.
5. Put the flow in `godot/PLAYTEST.md` (host on Steam, invite, friend clicks) and ARCHITECTURE.md
   (one paragraph). Live test waits on the P6-3 BLOCKED.md entry; say so.

**Already decided**
- Invites go through the Steam overlay dialog; no custom friends list UI. Lobby is friends-only.
- The backend of a join comes from the handle (`SessionHandle.backend`), never from a menu toggle.
- If Steam is not available, nothing Steam-related is shown in the menu or the lobby (log in
  DECISIONS.md, plain).

**Files likely touched**
- `godot/game/greybox/main_menu.gd`, `godot/game/greybox/lobby_panel.gd`, `godot/game/greybox/greybox_main.gd`
- `godot/net/steam_transport.gd` (an `available()` static and the overlay call, if P6-3 did not add them)
- `godot/PLAYTEST.md`, `godot/ARCHITECTURE.md`, `DECISIONS.md`, `PLAN.md`, `PROGRESS.md`

**Done means**
- With no Steam present: the menu and lobby look exactly as before (no Steam buttons), Host/Join by
  code still work; a headless `--solo` run prints no script errors.
- `+connect_lobby 109775241012345678` on the command line reaches the guest path with a steam handle
  and fails cleanly with the "Steam is not available" message.
- Full `node autobuild/verify.mjs` ONCE at the end, before the commit: healthy.

**Do NOT**
- Remove or change the code path, `LobbyCode`'s format or backend numbers (append-only).
- Download GodotSteam, create accounts, or publish anything.
- Add tests for menu/UI code (presentation is never tested), frames, sweeps, bot work.
