import * as THREE from "three";
import { WORLD_WIDTH, WORLD_HEIGHT } from "../constants";

// Minimal Three.js bootstrap: scene + renderer + a resize-aware camera + a
// render loop. Milestone A only needs an overview camera to verify the floor
// plan visually; Milestone B replaces `camera` usage with the real 3rd-person
// chase rig (CameraRig owns the camera from that point on, this class just
// keeps rendering whatever camera it's handed).
export class SceneManager {
  readonly scene = new THREE.Scene();
  camera: THREE.PerspectiveCamera;
  readonly renderer: THREE.WebGLRenderer;
  private container: HTMLElement;
  private onFrame?: (dt: number) => void;
  private lastTime = performance.now();

  constructor(container: HTMLElement) {
    this.container = container;

    this.camera = new THREE.PerspectiveCamera(60, container.clientWidth / container.clientHeight, 1, 5000);
    // Overview position for Milestone A's visual check - looking down at the
    // whole map from one corner.
    this.camera.position.set(WORLD_WIDTH / 2, 1400, WORLD_HEIGHT * 1.4);
    this.camera.lookAt(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);

    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    container.appendChild(this.renderer.domElement);

    this.scene.add(new THREE.AmbientLight(0xffffff, 0.7));
    const sun = new THREE.DirectionalLight(0xffffff, 0.8);
    sun.position.set(400, 900, 300);
    this.scene.add(sun);
    this.scene.background = new THREE.Color(0x0d1926);

    window.addEventListener("resize", this.handleResize);
  }

  private handleResize = () => {
    const { clientWidth, clientHeight } = this.container;
    this.camera.aspect = clientWidth / clientHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(clientWidth, clientHeight);
  };

  start(onFrame?: (dt: number) => void) {
    this.onFrame = onFrame;
    this.lastTime = performance.now();
    requestAnimationFrame(this.tick);
  }

  private tick = (now: number) => {
    const dt = Math.min((now - this.lastTime) / 1000, 1 / 20);
    this.lastTime = now;
    this.onFrame?.(dt);
    this.renderer.render(this.scene, this.camera);
    requestAnimationFrame(this.tick);
  };

  dispose() {
    window.removeEventListener("resize", this.handleResize);
    this.renderer.dispose();
    this.container.removeChild(this.renderer.domElement);
  }
}
