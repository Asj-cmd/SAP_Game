# Blocked — things only the user can do

The loop adds entries here: what, why, what you must do, and what it did instead.

## 2026-11-17 — GodotSteam is not installed (P6-3; code done, live test waits)
- **What:** `SteamTransport` is written and passes the transport contract against a fake Steam. `--backend=steam` fails cleanly ("Steam is not available ...") until the add-on is present.
- **Why it needs you:** the GodotSteam GDExtension bundles Valve's `steam_api64.dll` under the Steamworks SDK agreement, which you must accept; a build for Godot 4.7 may not exist yet.
- **What you do:** install GodotSteam (GDExtension, Godot 4.7) into `godot/addons/godotsteam/`, run the Steam client logged in; then `--backend=steam` works with app id 480 (`godot/steam_appid.txt`, dev only). Expect small fixes on first live run (shape of message `identity`, `sendMessageToUser` arguments). A real app id needs a Steamworks partner account and its app fee (money).
- **What the loop did instead:** the contract test on a fake; nothing downloaded.

## 2026-11-13 — Regular/Teen character bodies are only in the paid pack (not blocking)
- **What:** D10 names Quaternius "Regular male/female" (dad/mom) and "Teen male/female" (kids).
  The free *Universal Base Characters [Standard]* zip you downloaded has only two bodies:
  `Superhero_Male_FullBody` and `Superhero_Female_FullBody`. The Regular and Teen bodies are in
  the paid **Source** version.
- **Why it needs you:** buying it costs money (D10 / DECISIONS "Never").
- **What you could do:** nothing, and accept the substitute below. Or buy the Source version and
  drop its Regular/Teen glTFs into `autobuild/Incoming/`. Or point to another free CC0 body on
  the same rig.
- **What the loop does instead:** P2-1 builds the whole family from the two free bodies (same rig):
  adults full size, kids scaled down with bigger heads, with the muscle detail smoothed away by
  the deadpan material. Logged in DECISIONS.md as REVIEW. Nothing is waiting on this.
