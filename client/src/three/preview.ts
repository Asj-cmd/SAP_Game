// Temporary dev-only harness for visually verifying Milestone A (static 3D
// world) and Milestone B (character + camera) in isolation, before real
// multiplayer wiring exists. Deleted during the Milestone C cutover. Not
// referenced by main.ts / the production build.
import { SceneManager } from "./SceneManager";
import { buildEnvironment } from "./EnvironmentBuilder";
import { CharacterModel } from "./CharacterModel";
import { CharacterController, type InputState } from "./CharacterController";
import { CameraRig } from "./CameraRig";
import type { Team } from "../geometry/floorplan";

const container = document.getElementById("three-app")!;
const sceneManager = new SceneManager(container);

const input: InputState = { left: false, right: false, up: false, down: false };
window.addEventListener("keydown", (e) => setKey(e.key.toLowerCase(), true));
window.addEventListener("keyup", (e) => setKey(e.key.toLowerCase(), false));
function setKey(k: string, down: boolean) {
  if (k === "a" || k === "arrowleft") input.left = down;
  if (k === "d" || k === "arrowright") input.right = down;
  if (k === "w" || k === "arrowup") input.up = down;
  if (k === "s" || k === "arrowdown") input.down = down;
}

let wallsMesh: ReturnType<typeof buildEnvironment>["wallsMesh"] | null = null;
let floorMesh: ReturnType<typeof buildEnvironment>["floorMesh"] | null = null;
let controller: CharacterController | null = null;
let cameraRig: CameraRig | null = null;

async function rebuild(team: Team) {
  if (wallsMesh) sceneManager.scene.remove(wallsMesh);
  if (floorMesh) sceneManager.scene.remove(floorMesh);
  if (controller) sceneManager.scene.remove(controller.model.root);

  const env = buildEnvironment(team);
  wallsMesh = env.wallsMesh;
  floorMesh = env.floorMesh;
  sceneManager.scene.add(wallsMesh, floorMesh);

  const model = await CharacterModel.load(team);
  sceneManager.scene.add(model.root);
  // Living room interior, clear of every wall/door - safe for either team.
  const startX = team === "B" ? 300 : 1300;
  controller = new CharacterController(model, env.colliderRects, startX, 400);
  cameraRig = new CameraRig(sceneManager.camera, [wallsMesh]);
}

await rebuild("B");

sceneManager.start((dt) => {
  if (!controller || !cameraRig) return;
  controller.update(dt, input, false);
  cameraRig.update(dt, controller.x, controller.z, controller.model.getFacingAngle());
});

document.getElementById("teamB")!.addEventListener("click", () => rebuild("B"));
document.getElementById("teamA")!.addEventListener("click", () => rebuild("A"));
