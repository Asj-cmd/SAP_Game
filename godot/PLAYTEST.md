# Cash Grab — playtest build

A grey-box test. Plain boxes and capsules, no art, no sound. What is being
tested is how it **feels** to chase someone through a house and how the safe
room behaves — not how it looks.

Two people, one hosts, the other joins. Ten minutes is plenty.

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
godot --headless --path godot --export-release "Windows Desktop"
```

It lands in `build/CashGrab.exe` - one file, about 110 MB, no installer. Send
the whole thing to whoever is playing.

## 3. Run the game

Unzip anywhere and run **CashGrab.exe**. No installer.

Windows may warn about an unrecognised publisher - the build is not signed.
*More info* -> *Run anyway*.

The game opens on a menu with three choices.

### The host

Press **Host**. The address box is filled in for you: if Tailscale is running
it picks your Tailscale address (`100.x.y.z`), otherwise your home-network
address. The note under the box says which, and who can reach it.

A **code** like `05ZG-0001-W5FG` appears top-left and is **already copied** -
paste it to the other player in whatever chat you use.

> Use the Tailscale address when the other player is in a different house. A
> home-network address (`192.168.x.x`) only works for someone on the same wifi.

### The other player

Paste the code into **Join a game** and press **Join** (or Enter). Codes are not
case-sensitive and the dashes do not matter.

You should be in the match within a second. If the host cannot be reached you
are put back on the menu after about ten seconds with the reason, and the code
is still in the box to try again.

### On your own

**Team size** (above Play solo) picks 2v2, 3v3 or 4v4 - 3v3 to start with. It
applies to Play solo and to Host; bots fill every seat nobody is sitting in.
(1v1 is there for testing.) Joining needs no choice: you play at the host's size.

**Play solo** starts a match with you and bots.

**F10** leaves any match and goes back to the menu.

> The command-line flags still work (`CashGrab.exe -- --host`,
> `-- --join=CODE`, `-- --advertise=100.x.y.z`, `-- --team-size=4`) for anyone
> scripting a test.

## 4. Playing

| | |
|---|---|
| Move | `W A S D` |
| Look | mouse - the camera sits behind you and you run where it points |
| Jump | `SPACE` |
| Crouch (hold) | `SHIFT` |
| Grab / drop cash | left mouse button |
| Throw cash | right mouse button - a toss; it lands and anyone can pick it up |
| Seize an intruder, or free a team-mate | `E` |
| Leave to the menu | `F10` |
| Release the mouse | `Esc` |
| Save a screenshot | `F12` |
| Show / hide the debug HUD (score, timer, bot state) | `F1` - hidden by default until the real HUD lands |

Steal cash from the other family's vault and get it back to yours. On your own
ground you can seize an intruder, which sends them to your basement until a
team-mate reaches them - **except** in a safe room.

`E` is one button for both: it asks for a seize and a release at the same time
and the rules pick. Seizing needs an intruder on ground you own; freeing needs a
held team-mate within reach; no position satisfies both.

**You cannot seize someone in your own vault for the first 5 seconds after they
enter it** - that is the safe room, and it is deliberate. Nor in the garden
between the houses, which belongs to nobody, nor in your own basement. Anywhere
else on your own ground is fair game.

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

Known and not worth reporting: no sound, plain block characters with no
animation, and grey-box rooms.
