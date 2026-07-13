// Temporary dev-only harness for visually verifying Milestone A (static 3D
// world) and Milestone B (character + camera) in isolation, before real
// multiplayer wiring exists. Deleted during the Milestone C cutover. Not
// referenced by main.ts / the production build.
import { SceneManager } from "./SceneManager";
import { buildEnvironment } from "./EnvironmentBuilder";
import type { Team } from "../geometry/floorplan";

const container = document.getElementById("three-app")!;
const sceneManager = new SceneManager(container);
// Straight top-down check camera - easiest way to compare door gaps 1:1
// against the old 2D minimap during Milestone A verification.
sceneManager.camera.position.set(800, 1700, 450);
sceneManager.camera.up.set(0, 0, -1);
sceneManager.camera.lookAt(800, 0, 450);

let currentTeam: Team = "B";
let wallsMesh: ReturnType<typeof buildEnvironment>["wallsMesh"] | null = null;
let floorMesh: ReturnType<typeof buildEnvironment>["floorMesh"] | null = null;

function rebuild(team: Team) {
  currentTeam = team;
  if (wallsMesh) sceneManager.scene.remove(wallsMesh);
  if (floorMesh) sceneManager.scene.remove(floorMesh);
  const env = buildEnvironment(team);
  wallsMesh = env.wallsMesh;
  floorMesh = env.floorMesh;
  sceneManager.scene.add(wallsMesh, floorMesh);
}

rebuild(currentTeam);
sceneManager.start();

document.getElementById("teamB")!.addEventListener("click", () => rebuild("B"));
document.getElementById("teamA")!.addEventListener("click", () => rebuild("A"));
