# Graph Report - client  (2026-07-17)

## Corpus Check
- 27 files · ~18,477 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 239 nodes · 511 edges · 14 communities (12 shown, 2 thin omitted)
- Extraction: 99% EXTRACTED · 1% INFERRED · 0% AMBIGUOUS · INFERRED: 5 edges (avg confidence: 0.5)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ab3d4a67`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- HouseDresser.ts
- GameController.ts
- package.json
- HeightField.ts
- EnvironmentBuilder.ts
- CharacterModel.ts
- GameController
- constants.ts
- compilerOptions
- LobbyView
- WindowBuilder.ts
- HudOverlay

## God Nodes (most connected - your core abstractions)
1. `GameController` - 24 edges
2. `heightAt()` - 22 edges
3. `buildEnvironment()` - 17 edges
4. `CharacterModel` - 13 edges
5. `Rect` - 12 edges
6. `buildWindows()` - 12 edges
7. `HudOverlay` - 12 edges
8. `compilerOptions` - 12 edges
9. `Team` - 11 edges
10. `rectToBox()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `buildWindows()` --calls--> `teamSideAt()`  [EXTRACTED]
  src/three/world/WindowBuilder.ts → src/constants.ts
- `GameController` --references--> `Team`  [EXTRACTED]
  src/three/GameController.ts → src/geometry/floorplan.ts
- `HudOverlay` --references--> `Team`  [EXTRACTED]
  src/ui/HudOverlay.ts → src/geometry/floorplan.ts
- `RoofPanel` --references--> `ZoneId`  [EXTRACTED]
  src/three/world/RoofSystem.ts → src/geometry/floorplan.ts
- `doorFrameBase()` --calls--> `getZoneAt()`  [EXTRACTED]
  src/three/EnvironmentBuilder.ts → src/geometry/floorplan.ts

## Import Cycles
- None detected.

## Communities (14 total, 2 thin omitted)

### Community 0 - "HouseDresser.ts"
Cohesion: 0.14
Nodes (24): dressHouses(), mirrorPlacement(), mirrorRot(), placeIndividually(), solidRect(), buildInstancedProps(), dummy, applyMaterialRoles() (+16 more)

### Community 1 - "GameController.ts"
Cohesion: 0.16
Nodes (15): COLORS, ROOF_BASE, getZoneAt(), isEnemyBedroom(), isOwnHome(), jailBasementForTeam(), ZONE_RECTS, ZoneId (+7 more)

### Community 2 - "package.json"
Cohesion: 0.09
Nodes (22): colyseus.js, dependencies, colyseus.js, three, devDependencies, playwright-core, @types/three, typescript (+14 more)

### Community 3 - "HeightField.ts"
Cohesion: 0.15
Nodes (15): Door, Rect, CharacterController, Environment, Axis, clamp01(), corridorHeight(), heightAt() (+7 more)

### Community 4 - "EnvironmentBuilder.ts"
Cohesion: 0.23
Nodes (20): teamSideAt(), DOORS, buildEnvironment(), coloredBox(), doorBase(), doorFrameBase(), doorFrameGeoms(), foundationGeoms() (+12 more)

### Community 5 - "CharacterModel.ts"
Cohesion: 0.14
Nodes (11): Team, CharacterModel, FAMILY_ORDER, FamilyVariant, loadBundleTemplate(), pickFamilyVariant(), VARIANT_TOP, VARIANT_URL() (+3 more)

### Community 7 - "constants.ts"
Cohesion: 0.13
Nodes (5): DEFAULT_PITCH, FOLLOW_DISTANCE, CameraRig, clamp(), SceneManager

### Community 8 - "compilerOptions"
Cohesion: 0.12
Nodes (16): DOM, ES2020, src, compilerOptions, esModuleInterop, isolatedModules, lib, module (+8 more)

### Community 9 - "LobbyView"
Cohesion: 0.16
Nodes (4): LobbyView, onGameStart(), ColyseusClient, HOST

### Community 10 - "WindowBuilder.ts"
Cohesion: 0.26
Nodes (12): WALLS, WINDOWS, WindowSpec, buildWindows(), findWallIndex(), plainBox(), proudRunRect(), runRect() (+4 more)

## Knowledge Gaps
- **43 isolated node(s):** `name`, `version`, `private`, `type`, `dev` (+38 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **2 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `GameController` connect `GameController` to `GameController.ts`, `HeightField.ts`, `CharacterModel.ts`, `constants.ts`, `LobbyView`, `HudOverlay`?**
  _High betweenness centrality (0.089) - this node is a cross-community bridge._
- **Why does `HudOverlay` connect `HudOverlay` to `GameController.ts`, `CharacterModel.ts`, `GameController`?**
  _High betweenness centrality (0.048) - this node is a cross-community bridge._
- **Why does `heightAt()` connect `HeightField.ts` to `HouseDresser.ts`, `GameController.ts`, `EnvironmentBuilder.ts`, `CharacterModel.ts`, `GameController`, `constants.ts`?**
  _High betweenness centrality (0.044) - this node is a cross-community bridge._
- **What connects `name`, `version`, `private` to the rest of the system?**
  _43 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `HouseDresser.ts` be split into smaller, more focused modules?**
  _Cohesion score 0.13793103448275862 - nodes in this community are weakly interconnected._
- **Should `package.json` be split into smaller, more focused modules?**
  _Cohesion score 0.08695652173913043 - nodes in this community are weakly interconnected._
- **Should `CharacterModel.ts` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._