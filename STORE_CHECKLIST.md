# Steam store page checklist

A list only. Nothing here has been published or sent anywhere. Sizes are from memory:
**check each on Steamworks before making the asset.** Status: have / to make / user only.

## Accounts and fees (user only)

| What | Status |
|---|---|
| Steamworks partner account (identity, tax and bank details) | user only (see BLOCKED.md) |
| Steam Direct app fee per game | user only (money) |
| A real app id (replaces test id 480 in `godot/steam_appid.txt`; keep that file out of the export) | user only |
| GodotSteam add-on for Godot 4.7 installed in `godot/addons/godotsteam/` | user only (see BLOCKED.md) |

## Store page assets

| What | Size / format | Status |
|---|---|---|
| Capsule: header | 460x215 (check on Steamworks) | to make |
| Capsule: small | 231x87 | to make |
| Capsule: main | 616x353 | to make |
| Capsule: vertical | 374x448 | to make |
| Library capsule / hero / logo | 600x900 / 3840x1240 / 1280x720 (logo PNG, transparent) | to make |
| Page background | 1438x810 | to make |
| Screenshots | at least 5, 1920x1080 PNG or JPG, no UI mock-ups | to make (`F12` in game saves one; `autobuild/verify.mjs --frames` shoots every room) |
| Trailer | MP4, 1080p, 30-60 s, optional but strongly advised | to make |
| App icon / client icon | 32x32 and 184x184 | to make |

## Text

| What | Notes | Status |
|---|---|---|
| Short description | up to 300 characters | to make |
| Long description | with the credits list from `CREDITS.md` | to make |
| Tags and genre | party, multiplayer, co-op, 3D, funny, third person | to make |
| Supported languages | English only | have |
| System requirements | Windows 10 64-bit; runs at 90+ FPS on a GeForce GT 730M laptop at 1600x900, High (`godot/PLAYTEST.md`, P7-2); Low preset for weak or integrated GPUs; build is about 118 MB | have (numbers) / to make (form) |
| Controls and input | keyboard and mouse (a gamepad reads some buttons) | have |
| Online features | 2-8 players over Steam lobbies, bots fill empty seats | have |

## Forms and release

| What | Status |
|---|---|
| Content survey / age rating questionnaire (cartoon-free slapstick, no gore; bodies are blank figures) | user only |
| Price and regional pricing | user only |
| Build upload to a Steam depot, default branch, review submission | user only |
| Steam Input / achievements / cloud saves | not planned for v1 |
| Credits shown in game (Credits button on the main menu) | have |
| Third-party licences: all assets CC0 or MIT, listed in `ASSETS.md` and `CREDITS.md`; Godot's licence text ships with the game | have |
