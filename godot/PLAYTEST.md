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

## 2. Run the game

Unzip anywhere and run **CashGrab.exe**. No installer.

Windows may warn about an unrecognised publisher — the build is not signed.
*More info* → *Run anyway*.

### The host

Run it with `--host`:

- Make a shortcut, or
- Open the folder, type `cmd` in the address bar, and run:
  ```
  CashGrab.exe -- --host
  ```
  *(the bare `--` is not a typo — it separates the game's options from Godot's)*

Top-left it will show a **code** like `05ZG-0001-W5FG`. Read it to the other
player.

**The code contains this machine's Tailscale address**, so tell the host to use
their Tailscale IP: find it in the Tailscale window (it looks like
`100.x.y.z`), and start with

```
CashGrab.exe -- --host --advertise=100.x.y.z
```

### The other player

```
CashGrab.exe -- --join=05ZG-0001-W5FG
```

Codes are not case-sensitive and the dashes do not matter.

## 3. Playing

| | |
|---|---|
| Move | `W A S D` |
| Look | mouse |
| Grab / drop cash | `Q` |
| Seize an intruder | `E` |
| Free a team-mate | `R` |
| Release the mouse | `Esc` |
| Save a screenshot | `F12` |

Steal cash from the other family's vault and get it back to yours. On your own
ground you can seize an intruder, which sends them to your basement until a
team-mate reaches them — **except** in a safe room.

**Add bots** with `F3` on the host if you want more bodies in the match. They
fill both sides evenly or not at all.

## 4. What we want to know

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

## 5. If it goes wrong

| What you see | What it means |
|---|---|
| `that is not a session code` | Mistyped. `0` is a zero; there is no letter O in a code. |
| Nothing happens after joining | The host is not running, or Tailscale is not connected on one end. Check both machines are listed in the Tailscale window. |
| `NETWORK the host left` | Host closed the game. The match ends — there is no host migration yet. |
| Frozen for a second, then fine | A dropped packet. Expected; it repairs itself. Tell us if it happens a lot. |
| You stop moving but others carry on | Tell us. That one matters. |
| Dropped out entirely | Just run the same join command again. You get **your own body back**, wherever it had got to - a bot covers the seat while you are away and hands it straight back. If you come back as a *new* player instead, that is a bug and we want to know. |

Known and not worth reporting: no sound, no menus, no character art, and the
whole thing is grey boxes.
