# Briefs for the next open tasks

Written by the planner from a quick read. If a fact here is wrong, the code and `DECISIONS.md` win.

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
- `godot/net/steam_transport.gd` (`available()` exists; add the overlay call)
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
