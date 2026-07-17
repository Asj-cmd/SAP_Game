# Cash Grab — Master Plan (Living Anchor Doc)

The north star and phase map for taking Cash Grab from a working flat-plane 3D
multiplayer prototype to a polished, deployed, online 3D party game on Steam.
This is the reference every phase PRD is measured against. Update it when scope
or sequencing genuinely changes; otherwise leave it be.

---

## 1. Vision

A **professional, chaotic, funny/offbeat, third-person 3D multiplayer party
game** shipped on **Steam**. Two families raid each other's houses to steal
cash, jail intruders, and rescue teammates. The feel we're chasing: the rough,
readable, "one-more-round" energy of viral indie party games (Meccha Chameleon's
UI vibe as a reference), but an entirely original concept, world, and cast.

**Guiding constraints:** validate cheaply (near-$0 until proven), keep the loop
fun first, ship on Steam. Distinctive art is the human bottleneck; everything
else Claude Code can carry.

---

## 2. Fixed Architecture (do not drift from this without a decision)

- **Server:** Colyseus + TypeScript, fully **authoritative**. It is
  engine-agnostic — it only knows player positions, cash state, and 2D zone
  rectangles (`server/src/zones.ts`, `getZoneAt(x,y)`). The client never mutates
  game state; it sends intent, the server validates. This is our anti-cheat
  foundation. Keep it.
- **Client:** **Three.js** (vanilla, web-3D). One orchestrator
  (`client/src/three/GameController.ts`) owns the render loop, local
  character/camera, remote sync, cash view, HUD, and action detection.
- **World model:** currently a **single flat plane** (Brawl-Stars-style top-down
  rendered as a 3rd-person chase cam). No height axis, no gravity, no jump.
  "Bedroom / living / basement" are labeled floor regions side-by-side, not
  vertical floors. True verticality is a deliberate future decision (Phase 5).
- **Asset pipeline:** two complementary paths — (a) **headless Blender bpy
  scripts** (`assets/blender/build_*.py`, run via `blender --background
  --python`) for deterministic, committed props; and (b) **Blender MCP** (from
  Phase 4) for interactive character/world authoring with viewport-screenshot
  feedback + PolyHaven/Hyper3D assets. Blender MCP output is exported to
  committed `.glb` (and optionally back-filled into a bpy script) so the runtime
  stays asset-based and needs no Blender to play. See
  `PROJECT_STATUS_AND_HANDOFF.md` §5.
- **Path to Steam:** web build wrapped in **Electron + steamworks.js** (Tauri as
  a lighter alt). Validate for free on the web (itch.io) *before* the $100 Steam
  fee.
- **Cost posture:** $0 through the first web validation gate; ~$5–20/mo only when
  always-on servers are needed; $100 one-time for Steam.

---

## 3. Working Model (how this project is run)

- **`claude/game-mvp-dev-pl5suo`** — the source of truth for CODE. Always read
  the latest there before planning or building.
- **`claude/cash-grab-game-skills-qxd4ne`** (this branch) — PLANNING only:
  master plan, phase PRDs, skill discovery. No game code here.
- **Per-phase PRDs** in `prds/`, written in the rigorous style of the original
  `cash-grab-prd.md` (precise, "don't add unlisted features", "stop and ask
  before uncovered architectural decisions"). One focused PRD per phase.
- **Standing rules baked into every PRD:**
  1. **No test code / test files / test functions / test scripts of any kind.**
     Verify via build + a manual checklist only. (Saves tokens; near-identical
     output.)
  2. **Keep code properly structured** — single-purpose files, named exports, no
     dead code, reuse over duplication.
  3. Server stays authoritative; one coordinate mapping (server `x,y` → Three
     `x,z`, `y` = up); no unlisted mechanics.

---

## 4. Phase Map (reality-anchored)

| Phase | Name | Status | Core outcome |
|---|---|---|---|
| 1 | 2D Concept MVP | ✅ done | Phaser + Colyseus, full game logic |
| 2 | 3D Cutover (Milestones A–D) | ✅ done | Flat-plane 3D multiplayer: world, assets, controller, mouse-look chase cam, multiplayer wiring, host lobby + AI bots |
| 3 | Real Houses & World Believability | ✅ done | Roofs w/ per-room reveal, see-through windows, 17 furnished props, instancing, ACES tone mapping + soft shadows. No server/physics change. |
| **4** | **Characters & Chaos** | **▶ next** | Original funny/offbeat cast authored via **Blender MCP** + **Rapier physics**: knockback, ragdoll, dropped-cash, shove/tackle. Biggest "is it fun" lever. |
| 5 | Verticality & Houses v2 | planned (ambitious; optional for first Steam pass) | True multi-floor, **functional stairs**, jump-through windows; server gains a height/floor axis. Depends on Phase 4 physics. |
| 6 | Game Feel & UI Polish | planned | Meccha-style HUD/menus, audio, VFX/juice, settings. |
| 7 | Online Hardening | planned | Deploy Colyseus, matchmaking, reconnection, regions, anti-cheat basics. |
| 8 | Steam Packaging | planned | Electron + steamworks.js; Windows + Steam Deck. |
| 9 | Launch | planned | Store page (start early for wishlists), capsule/key art, trailer, release. |
| 10 | Post-launch | planned | Patches, new maps/characters, server scaling, community. |

**Validation gates:**
- **Gate 1 (free web build):** after Phase 4. Deploy client to itch.io + server
  to a free tier. Watch real people play. Go/no-go before spending more.
- **Gate 2 (Steam playtest/demo):** after Phase 8. Validate retention/virality
  before a paid launch.

**Sequencing note:** Phase 4 (characters & chaos) is the single biggest fun
lever. If Gate 1 playtests say the loop needs more juice before it needs prettier
houses, Phases 3 and 4 can swap order. Environment-first is the current call
because the world currently reads as colored boxes and that's the more concrete
next step.

---

## 5. Installed Skills (for building phases)

- **`threejs-game-skills`** bundle (973★, majidmanzarpour) — installed globally:
  - `threejs-game-director` (orchestrator), `threejs-gameplay-systems`,
    `threejs-aaa-graphics-builder` (materials/lighting/VFX — key for Phase 3),
    `threejs-game-ui-designer`, `threejs-debug-profiler`, `threejs-qa-release`.
  - Optional, **need paid API keys** (skip under low-cost default):
    `threejs-3d-generator` (Tripo), `threejs-image-generator` (Gemini),
    `threejs-audio-generator` (ElevenLabs).
- **`find-skills`** (vercel) — installed; discover/install more skills on demand.
- **`canvas-design`** / **`artifact-design`** (Anthropic) — store/key art and UI
  mockups when those phases arrive.
- **Not installed:** `cc-blender-skill` (needs a live Blender+MCP instance; our
  pipeline is headless bpy, so Claude writes the scripts directly).

---

*Living doc. The current active build target is always defined by the newest PRD
in `prds/` and the code on `claude/game-mvp-dev-pl5suo`.*
