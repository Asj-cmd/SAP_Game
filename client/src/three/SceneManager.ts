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
    // PCFSoftShadowMap was silently downgraded to hard-edged PCFShadowMap by
    // this Three.js version (with a console warning) - VSMShadowMap is the
    // current supported way to get soft shadow edges, tuned via
    // light.shadow.radius/blurSamples below instead of the shadow type alone.
    this.renderer.shadowMap.type = THREE.VSMShadowMap;
    // Deliberate tone mapping + exposure (previously unset/NoToneMapping,
    // which read as flat and muddy indoors): ACES gives filmic roll-off on
    // the sunlit exteriors while exposure keeps the window-lit interiors
    // readable instead of crushed toward black.
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.2;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(this.renderer.domElement);

    // Key-to-fill ratio is the whole game here: the old 0.7 hemisphere + 0.35
    // ambient (~1.05 combined) nearly matched the 1.3 sun, so shadowed and lit
    // faces collapsed into one flat midtone band. Fill totals ~0.6 against a
    // 2.0 key (~3.3:1) - the hemisphere is a touch above the look-pass's 0.35
    // to lean "sunny morning" rather than "moody", without flattening the
    // contrast that pass earned; shadow sides still read clearly darker.
    this.scene.add(new THREE.HemisphereLight(0xcfe3f5, 0x4a5442, 0.45));
    this.scene.add(new THREE.AmbientLight(0xfff2e0, 0.15));

    // Crisper near-white key (was amber 0xfff4e6, which read sunset).
    const sun = new THREE.DirectionalLight(0xfffbf2, 2.0);
    sun.name = "sun";
    sun.position.set(WORLD_WIDTH * 0.3, 1400, WORLD_HEIGHT * 0.2);
    sun.target.position.set(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0005;
    // VSM softness: normalBias avoids the light-leak VSM otherwise causes on
    // thin geometry (window sills/prop edges), radius controls blur width.
    sun.shadow.normalBias = 0.6;
    sun.shadow.radius = 3;
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

    // Bright morning sky (the old 0x0d1926 navy void made the sunlit world
    // look like it was floating in night). Flat color + matching fog is
    // deliberately cheap - a gradient dome isn't worth a draw call yet.
    const SKY_COLOR = 0x8ecdf2;
    this.scene.background = new THREE.Color(SKY_COLOR);
    // Cheap depth cue (built-in fog, no post-processing): the far house fades
    // toward the sky color, separating "my room" from "across the map" scale.
    // Derived from WORLD_WIDTH so it stays correct at any WORLD_SCALE without
    // retuning: near starts past the whole near house (interiors untouched) and
    // far lands the opposite house ~25-30% fogged. The 0.625/1.75 factors
    // reproduce the hand-tuned 2000/5600 that read well at the 2.0 map size.
    this.scene.fog = new THREE.Fog(SKY_COLOR, WORLD_WIDTH * 0.625, WORLD_WIDTH * 1.75);

    // Visible sun disc: a DirectionalLight has no geometry, so without this
    // the light direction had no anchor anywhere in frame. Placed at the
    // light's exact AZIMUTH (so it agrees with every shadow's direction on
    // the ground) but at a low ~24-degree morning elevation - the literal
    // light sits at ~66 degrees, which the camera's pitch clamp can never
    // frame, and a low sun is what "morning" looks like anyway. Unlit
    // material, excluded from fog so it never fades out at distance.
    const SUN_DISC_DISTANCE = 3800;
    const SUN_DISC_RADIUS = 170;
    const SUN_DISC_ELEVATION = 0.42; // radians
    const toSun = sun.position.clone().sub(sun.target.position);
    const azimuth = Math.atan2(toSun.x, toSun.z);
    const sunDisc = new THREE.Mesh(
      new THREE.SphereGeometry(SUN_DISC_RADIUS, 16, 12),
      new THREE.MeshBasicMaterial({ color: 0xfff3c4, fog: false })
    );
    sunDisc.position
      .copy(sun.target.position)
      .add(
        new THREE.Vector3(
          Math.sin(azimuth) * Math.cos(SUN_DISC_ELEVATION) * SUN_DISC_DISTANCE,
          Math.sin(SUN_DISC_ELEVATION) * SUN_DISC_DISTANCE,
          Math.cos(azimuth) * Math.cos(SUN_DISC_ELEVATION) * SUN_DISC_DISTANCE
        )
      );
    this.scene.add(sunDisc);

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
