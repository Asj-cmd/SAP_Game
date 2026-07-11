# Cash Grab

A 2v2 multiplayer side-scrolling browser game. Two families of 2 players each
compete to steal cash bundles from each other's master bedroom, jail the
intruders they catch at home, and rescue jailed teammates. First to bank **5**
bundles wins the round — best of 3.

Built with **Phaser 3** (client) + **Colyseus** (server) + **TypeScript** + **Vite**.
See `cash-grab-prd.md` for the full spec.

---

## Play with your friends (the easy way)

The game server can also serve the game page, so **everyone uses one single link** —
no separate client to run.

### 1. One-time setup

```bash
npm run install:all
```

(Installs both the client and server. Requires Node.js 18+.)

### 2. Start the game

```bash
npm run play
```

This builds the game and starts the server. When it's ready you'll see:

```
Cash Grab server running on port 2567
```

Now open **http://localhost:2567** in your browser, type your name, and click
**Create Room**. You'll get a 4-letter **room code** (e.g. `AEKF`).

### 3. Get your friends in

Pick whichever matches where your friends are:

**A) Same WiFi / same house (easiest)**
1. Find your computer's local IP address:
   - **macOS:** `ipconfig getifaddr en0`
   - **Windows:** `ipconfig` → look for "IPv4 Address"
   - **Linux:** `hostname -I`
   - It looks like `192.168.1.23`.
2. Tell your friends to open **`http://<your-ip>:2567`** (e.g. `http://192.168.1.23:2567`).
3. They type their name, enter your **room code**, and click **Join**.

**B) Friends somewhere else (over the internet)**

Your friends can't reach your `localhost`/home IP, so expose the one port with a
free tunnel. Using [cloudflared](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/)
(no account needed):

```bash
# in a second terminal, while `npm run play` is running
cloudflared tunnel --url http://localhost:2567
```

It prints a public HTTPS URL like `https://random-words.trycloudflare.com`.
Share **that URL** with your friends — they open it, enter your **room code**, and
join. (Any tunnel works: ngrok `ngrok http 2567`, VS Code port forwarding, etc.)

The game auto-starts the moment **4 players** are in the room (first 2 to join are
Team B / orange, next 2 are Team A / blue).

> Want to test alone first? Open **http://localhost:2567** in 4 browser tabs and
> create/join with the room code — each tab is a player.

---

## Controls

- **A/D** or **←/→** — move
- **W** or **↑** — jump
- **SPACE** — context action: pick up cash, **lock** an enemy caught in your house,
  rescue a jailed teammate, or steal an already-scored bundle. A prompt appears
  above your character whenever SPACE will do something.
- Carried cash **banks automatically** the moment you step back into your own home.

## How to read the game

- The **minimap** (top) shows the whole house and where everyone is — your dot has
  a white ring.
- There's **no score counter** by design: to see the score, look at the cash
  stacked in each master bedroom (also shown in the world). Whoever has more
  bundles in their bedroom is winning.
- Carrying cash slows you down, so watch for defenders.

---

## For developers

Run the client and server separately with hot-reload:

```bash
npm run dev:server   # Colyseus on ws://localhost:2567
npm run dev:client   # Vite on http://localhost:5173  (open this one)
```

In dev mode the client automatically talks to the server on port 2567. Friends on
your LAN can also open `http://<your-ip>:5173` during development.

Advanced server override (point the client at a specific server):
- add `?server=host:port` to the URL, or
- build the client with `VITE_SERVER_URL=host:port`.

```
cash-grab/
├── client/    # Phaser 3 frontend (scenes, objects, network, constants)
├── server/    # Colyseus game server (room logic, schema, zones)
└── package.json  # convenience scripts: install:all, play, dev:server, dev:client
```

## Status

Phase 1 MVP. Stick-figure players, colored-zone world, no sound/art yet (by
design for this phase). All mechanics — pickup, carry, auto-deposit, lock/jail,
rescue, auto-release, steal-back, win at 5, round reset, best-of-3 — are
implemented and verified with both a scripted 4-client logic test and a 4-tab
browser test. Known-closed loopholes: score can't drift or be drained for free
(a caught thief returns the point to the team that earned it), jailed players
can't rescue, and a bundle carried by someone who disconnects returns to play.
