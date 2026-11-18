# Cash Grab — playtest build

A friends playtest of the whole game: two families, two houses, bots filling
every empty seat. What is being tested is how it **feels** to raid a house and
chase someone through it. Sound levels and looks are fair to comment on too.

One person hosts, the others join. Fifteen minutes is plenty.

---

## 1. Get on the same network (5 minutes, once)

Home routers do not accept incoming connections, so the two machines cannot
reach each other directly across the internet. **Tailscale** puts them on a
private network as though they were in the same room. It is free, it does not
need router settings changed, and it can be uninstalled afterwards.

1. Both of you: install it from **https://tailscale.com/download**
2. Sign in with the same method (Google, Microsoft, GitHub — whatever you both
   have). *You must both use the same account, or share the network from the
   Tailscale admin page.*
3. Open the Tailscale window. You should see the other machine listed.

That is the whole setup. Leave it running in the background.

> **Why not just play over the internet?** The proper answer is Steam, which
> relays the connection for you. That is coming; it is not here yet, and it
> should not be what stops us testing.

## 2. Get the build

If you have one already, skip to running it. To make one from the source:

```
node autobuild/build.mjs
```

It lands in `build/CashGrab.exe` - one file, about 118 MB, no installer. Send
the whole thing to whoever is playing.

## 3. Run the game

Unzip anywhere and run **CashGrab.exe**. No installer.

Windows may warn about an unrecognised publisher - the build is not signed.
*More info* -> *Run anyway*.

The game opens on a menu: **Play solo**, **Host** (and **Host on Steam** when
that add-on is installed), **Join**, **Settings**, **How to play**, **Credits**
and **Quit**.

### The host

Press **Host**. The address box is filled in for you: if Tailscale is running
it picks your Tailscale address (`100.x.y.z`), otherwise your home-network
address. The note under the box says which, and who can reach it.

A **lobby panel** shows a **code** like `05ZG-0001-W5FG`, already copied - paste
it to the other players in whatever chat you use. The panel also has the team
size, a "fill empty seats with bots" box, **Start** (press it when everyone is
in) and **Cancel**.

> Use the Tailscale address when the other player is in a different house. A
> home-network address (`192.168.x.x`) only works for someone on the same wifi.

### The other player

Paste the code into **Join a game** and press **Join** (or Enter). Codes are not
case-sensitive and the dashes do not matter.

You land in the host's lobby within a second and the match starts when the
host presses Start. If the host cannot be reached you
are put back on the menu after about ten seconds with the reason, and the code
is still in the box to try again.

### On your own

**Team size** (above Play solo) picks 2v2, 3v3 or 4v4 - 3v3 to start with. It
applies to Play solo and to Host; bots fill every seat nobody is sitting in.
(1v1 is there for testing.) Joining needs no choice: you play at the host's size.

**Play solo** starts a match with you and bots.

**Esc** opens the pause menu (Resume, Settings, Leave to menu); the match keeps
running while it is up, online or not. **F10** leaves any match at once. The
first match shows a short step-by-step guide; **F9** skips it and *How to play*
on the menu brings it back.

> The command-line flags still work (`CashGrab.exe -- --host`,
> `-- --join=CODE`, `-- --advertise=100.x.y.z`, `-- --team-size=4`) for anyone
> scripting a test.

**Dedicated host** (a machine that serves but does not play, e.g. a spare PC):

```
godot --headless --path godot -- --dedicated --team-size=3 [--advertise=100.x.y.z] [--dedicated-wait=15]
```

It prints `DEDICATED HOST code=...` once; friends use that code with Join. The
match starts 15 s after the first guest sits down (bots fill empty seats) and
restarts by itself 12 s after each result.

## 4. Playing

| | |
|---|---|
| Move | `W A S D` |
| Look | mouse - the camera sits behind you and you run where it points |
| Jump | `SPACE` |
| Crouch (hold) | `SHIFT` |
| Grab / drop cash | left mouse button |
| Throw cash | right mouse button - a toss; it lands and anyone can pick it up |
| Seize an intruder, or free a team-mate | `E` (rebindable in Settings) |
| Play again when the match is over | `Enter` (solo or host; a guest waits for the host) |
| Leave to the menu | `F10` |
| Pause menu (the match keeps running) | `Esc` |
| Save a screenshot | `F12` |
| Show / hide the debug HUD (bot state, camera, network) | `F1` - hidden by default |

Name your family in the lobby before the host presses Start: each family has a
name box, anyone on that family can type its surname (up to 16 letters; it shows
as "<Surname> Family"), and the host can clear either. An empty box shows
"Green Family" or "Orange Family". In a solo game the two boxes are on the main
menu. See `HOW_TO_PLAY.md`.

Every round starts with your family lined up on your own front lawn, facing you,
for 3 seconds: your family's name above, and under each body its role (Dad, Mom,
Daughter, Son) and who plays it ("You", "Bot", or the player). Nobody can move
until the countdown ends, then the camera goes back behind you.

The bar across the top is a tug of war: each family's colour fills from its own
end in proportion to its banked cash, with the family names, cash, round wins and
the clock. CARRYING CASH or a JAILED countdown shows for you, and a prompt appears
when you can free a team-mate. A big message in the middle counts down each round
and says who won it, and who won the match. The results panel at the end offers
a rematch. A bundle someone is carrying is drawn over their
head.

Steal cash from the other family's vault and get it back to yours. On your own
side of the fence you can seize an intruder, which sends them to your jail until a
team-mate reaches them - **except** in a safe room. There is no neutral ground:
the boundary fence between the two lots is the line. Cross it through the central
gate or the small back crossing. Each house also has an outside back staircase to
the upstairs landing.

`E` is one button for both: it asks for a seize and a release at the same time
and the rules pick. Seizing needs an intruder on ground you own; freeing needs a
held team-mate within reach; no position satisfies both.

**You cannot seize someone in your own vault for the first 5 seconds after they
enter it** - that is the safe room, and it is deliberate. Nor in your own
jail. Anywhere else on your own side is fair game.

**Bots fill every empty seat**, and a joining player takes one over from a bot
(the emptier team gets them first). At 3v3 that is up to six people per match.

## 5. What we want to know

Please say what you actually felt, not what you think is useful. "I don't know,
it was annoying" is a better report than a theory.

1. **The safe room.** You are protected for a few seconds after entering the
   cash room. Too long? Too short? Did you ever notice it at all?
2. **Speed.** Does a chase across the yard feel fast or laboured? Does a house
   feel big or cramped?
3. **Getting caught.** When you were seized, was it fair? Did it look like they
   caught you, or like the game decided they had?
4. **Anything that felt wrong**, even if you cannot say why. Especially that.

Press `F12` when something looks wrong. Screenshots land in
`%APPDATA%\Godot\app_userdata\Cash Grab\`.

## 6. If it goes wrong

| What you see | What it means |
|---|---|
| `that is not a session code` | Mistyped. `0` is a zero; there is no letter O in a code. |
| `could not reach the host` | The host has not pressed Host yet, the code is wrong, or the host used a home-network address and you are in a different house. Ask them to host with Tailscale running, and check both machines are listed in the Tailscale window. |
| `NETWORK the host left` | Host closed the game. The match ends — there is no host migration yet. |
| Frozen for a second, then fine | A dropped packet. Expected; it repairs itself. Tell us if it happens a lot. |
| You stop moving but others carry on | Tell us. That one matters. |
| Dropped out entirely | Just run the same join command again. You get **your own body back**, wherever it had got to - a bot covers the seat while you are away and hands it straight back. If you come back as a *new* player instead, that is a bug and we want to know. |

## Playing over Steam (needs GodotSteam; see BLOCKED.md)

The Steam buttons appear only when the add-on is installed. Not tested live.

1. Host: main menu, pick a team size, **Host on Steam**. The lobby panel has **Invite friends (Steam)** (opens the Steam overlay invite dialog) and the code, which also works pasted into Join.
2. Friend: accepts the invite in Steam. If the game is closed Steam starts it with `+connect_lobby <id>`; if it is running the invite joins at once (not mid-match).
3. Tailscale/LAN: unchanged, Host and Join with the code.

Known and not worth reporting: the blank faces (deliberate), bot behaviour, and
Steam buttons missing (they need the add-on).

## Performance on the dev machine

Measured windowed on a **GeForce GT 730M** laptop (Compatibility renderer, 1600x900, 4v4, bots running),
`node autobuild/render_stats.mjs --args="--team-size=4 --quality=<preset>"`, 120 timed frames per view.
FPS = 1000 / median frame ms. The p95 frame (24-32 ms) is the occasional bot tick, not the render.

| Preset | View | Frame ms | GPU ms | FPS | Draws |
|---|---|---|---|---|---|
| high | approach_from_south | 9.2 | 6.2 | 109 | 420 |
| high | room_b_gf_kitchen | 10.8 | 8.3 | 93 | 332 |
| high | cam_railing_backed | 10.9 | 7.8 | 92 | 366 |
| medium | approach_from_south | 8.4 | 5.5 | 119 | 420 |
| medium | room_b_gf_kitchen | 10.2 | 7.8 | 98 | 332 |
| medium | cam_railing_backed | 10.4 | 7.2 | 96 | 366 |
| low | approach_from_south | 7.1 | 4.5 | 141 | 222 |
| low | room_b_gf_kitchen | 8.8 | 6.4 | 114 | 179 |
| low | cam_railing_backed | 8.6 | 5.9 | 116 | 191 |

High is the default and is already above 90 FPS here, so a friend on an ordinary laptop should stay on
**High**; on a weak or integrated GPU pick **Low** (no sun shadow, 75% render scale, about 25% less GPU
time and half the draw calls). Settings: *Graphics quality*, *Max FPS*, *Fullscreen*, *VSync* in the
settings panel; `--quality=low|medium|high` overrides the saved choice.
