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
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(this.renderer.domElement);

    // Sky/ground fill (no shadows) + a low ambient floor, so shadowed faces
    // never go fully black, plus one shadow-casting "sun" that does the real
    // modeling - real houses need real shadows for Phase 3's roofs/props to
    // read as solid.
    this.scene.add(new THREE.HemisphereLight(0xbfd4e8, 0x4a5442, 0.55));
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.25));

    const sun = new THREE.DirectionalLight(0xffffff, 1.1);
    sun.name = "sun";
    sun.position.set(WORLD_WIDTH * 0.3, 1400, WORLD_HEIGHT * 0.2);
    sun.target.position.set(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0005;
    // Orthographic shadow frustum sized to cover the whole world plus a
    // margin, since the sun's rays are parallel (no perspective falloff).
    const SHADOW_MARGIN = 400;
    const shadowCam = sun.shadow.camera;
    shadowCam.left = -WORLD_WIDTH / 2 - SHADOW_MARGIN;
    shadowCam.right = WORLD_WIDTH / 2 + SHADOW_MARGIN;
    shadowCam.top = WORLD_HEIGHT / 2 + SHADOW_MARGIN;
    shadowCam.bottom = -WORLD_HEIGHT / 2 - SHADOW_MARGIN;
    shadowCam.near = 10;
    shadowCam.far = 3000;
    shadowCam.updateProjectionMatrix();
    this.scene.add(sun, sun.target);

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
