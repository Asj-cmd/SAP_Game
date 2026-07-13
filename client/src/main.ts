import type { Room } from "colyseus.js";
import { LobbyView } from "./lobby/LobbyView";
import { GameController } from "./three/GameController";

const appRoot = document.getElementById("app")!;
const canvasRoot = document.getElementById("canvas-root")!;
const hudRoot = document.getElementById("hud-root")!;

function onGameStart(room: Room) {
  appRoot.style.display = "none";
  canvasRoot.style.display = "block";
  hudRoot.style.display = "block";
  GameController.start(canvasRoot, hudRoot, room);
}

new LobbyView(appRoot, onGameStart);
