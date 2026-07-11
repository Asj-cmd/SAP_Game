# Cash Grab

A 2v2 multiplayer side-scrolling browser game. Two families of 2 players each
compete to steal cash bundles from each other's master bedroom, lock intruders
in jail, and rescue jailed teammates. Best of 3 rounds, first to 5 bundles
scored wins a round.

Built with **Phaser 3** (client) + **Colyseus** (server) + **TypeScript** + **Vite**,
per the Phase 1 MVP spec in `cash-grab-prd.md`.

## Install

```bash
cd server && npm install
cd ../client && npm install
```

## Run locally

```bash
# Terminal 1 - server
cd server && npm run dev
# Server starts at ws://localhost:2567

# Terminal 2 - client
cd client && npm run dev
# Client starts at http://localhost:5173
```

Open `http://localhost:5173`, enter a name, and click **Create Room** to get a
4-character room code. Open 3 more browser tabs and use **Join Room** with that
code. The match starts automatically once 4 players have joined (first 2 to
join are Team B, next 2 are Team A).

## Playing with friends

**Same WiFi / LAN:** the client dev server already binds to your network
(`vite.config.ts` sets `host: true`). Find your machine's LAN IP (e.g.
`192.168.1.23`) and have friends open `http://<your-ip>:5173` instead of
`localhost`. The client automatically talks to the server on the same host,
port 2567, so no extra config is needed.

**Over the internet:** friends on a different network can't reach your
`localhost`/LAN address, so the **server** needs to be reachable publicly:

1. Deploy the `server/` folder somewhere public (a free tier on Render,
   Railway, or Fly.io all work well - it's a plain Node/Express/WebSocket
   process; run `npm install && npm run build && npm start`, or `npm run dev`
   for quick testing). Note the public host it gives you, e.g.
   `cash-grab-server.onrender.com`.
2. Point the client at it, either:
   - Share a link with a `?server=` query param, e.g.
     `https://your-client-url/?server=cash-grab-server.onrender.com`, or
   - Set `VITE_SERVER_URL=cash-grab-server.onrender.com` when building the
     client (`npm run build` in `client/`) if you're deploying the client too
     (e.g. to Vercel/Netlify/GitHub Pages).
3. Share the client URL (with the `?server=` param, if used) and the 4-char
   room code with your friends.

Without either of these, `npm run dev` only serves the game on your own
machine.

## Controls

- **A/D** or arrow keys - move
- **W** or up arrow - jump
- **SPACE** - context action (pick up cash, lock an enemy, rescue a jailed
  teammate, or steal an already-scored bundle back) - a prompt appears above
  your character when SPACE will do something
- Depositing carried cash happens automatically the moment you cross back into
  your own living room or bedroom

## Project structure

```
cash-grab/
├── client/    # Phaser 3 frontend (scenes, objects, network, constants)
└── server/    # Colyseus game server (room logic, schema)
```

## Status

Phase 1 MVP - see `cash-grab-prd.md` for the full spec. Stick-figure players,
colored-rectangle zones, no sound/art yet (by design for this phase). All
mechanics in the PRD's Section 8 checklist (pickup/deposit/lock/jail/rescue/
steal-back/win condition/round reset/best-of-3) are implemented and have been
verified against a scripted 4-client run of the server logic.
