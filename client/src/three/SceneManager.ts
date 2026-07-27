import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { WORLD_WIDTH, WORLD_HEIGHT, SKY, LIGHTING, POST } from "../constants";
import { buildSkyDome } from "./world/SkyDome";

// Scene + renderer + lighting + post-processing, and the render loop.
//
// The look is built out of four things, in order of how much they matter:
//
//   1. A real gradient SKY (world/SkyDome), baked to an environment map with
//      PMREM. Every MeshStandardMaterial in the game then has something to
//      reflect, which is the single biggest reason the world stopped reading as
//      untextured boxes: image-based lighting gives curved surfaces a gradient
//      and flat ones a subtle sheen, for one texture and no per-frame cost.
//   2. A three-light rig - warm key with tightly-framed shadows, cool sky fill,
//      and a back rim that separates characters from the wall behind them.
//   3. ACES tone mapping with a deliberate exposure, so saturated colours roll
//      off filmically instead of clipping.
//   4. A restrained bloom on the highlights only, which is what sells "lit"
//      rather than "coloured".
//
// Everything here is driven by the LIGHTING / SKY / POST tables in constants.ts
// - this file has no tuning numbers of its own.

export class SceneManager {
  readonly scene = new THREE.Scene();
  camera: THREE.PerspectiveCamera;
  readonly renderer: THREE.WebGLRenderer;
  private composer: EffectComposer;
  private sky: THREE.Mesh;
  private container: HTMLElement;
  private onFrame?: (dt: number) => void;
  private lastTime = performance.now();
  private disposed = false;

  constructor(container: HTMLElement) {
    this.container = container;

    // Far clip derives from WORLD_WIDTH so the whole map stays inside the
    // frustum at any WORLD_SCALE. Near is deliberately not 0.1: depth precision
    // is a ratio, and a tight near plane is what makes distant coplanar
    // surfaces fight.
    this.camera = new THREE.PerspectiveCamera(58, container.clientWidth / container.clientHeight, 4, WORLD_WIDTH * 2.2);
    this.camera.position.set(WORLD_WIDTH / 2, WORLD_WIDTH * 0.35, WORLD_HEIGHT * 1.4);
    this.camera.lookAt(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);

    this.renderer = new THREE.WebGLRenderer({ antialias: true, powerPreference: "high-performance" });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.VSMShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = LIGHTING.exposure;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(this.renderer.domElement);

    // ---- sun direction drives the sky, the key light and the shadows, so all
    // three always agree about where the light is coming from.
    const sunDir = new THREE.Vector3(...LIGHTING.sunDirection).normalize();

    // The dome RIDES THE CAMERA and is sized well inside the far plane. A dome
    // big enough to enclose the world gets clipped by that plane wherever it is
    // further away than the far clip, which punched a black hole in the sky.
    // Following the camera makes it unreachable and always fully in frustum.
    this.sky = buildSkyDome(this.camera.far * 0.4, SKY, sunDir);
    this.scene.add(this.sky);
    this.renderer.setClearColor(SKY.horizon, 1); // anything the dome misses

    // ---- image-based lighting, rendered once from the sky dome itself.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
    pmrem.compileEquirectangularShader();
    const envScene = new THREE.Scene();
    envScene.add(buildSkyDome(10, SKY, sunDir));
    this.scene.environment = pmrem.fromScene(envScene, 0.04).texture;
    this.scene.environmentIntensity = LIGHTING.environmentIntensity;
    pmrem.dispose();

    // ---- key: the sun. Its shadow camera is framed to the WORLD, not to some
    // arbitrary margin, so the shadow texels are spent on the play area.
    const sun = new THREE.DirectionalLight(LIGHTING.sunColor, LIGHTING.sunIntensity);
    sun.name = "sun";
    const centre = new THREE.Vector3(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);
    sun.position.copy(centre).addScaledVector(sunDir, WORLD_WIDTH * 0.8);
    sun.target.position.copy(centre);
    sun.castShadow = true;
    sun.shadow.mapSize.set(LIGHTING.shadowMapSize, LIGHTING.shadowMapSize);
    sun.shadow.bias = -0.0004;
    sun.shadow.normalBias = 0.5;
    sun.shadow.radius = LIGHTING.shadowSoftness;
    sun.shadow.blurSamples = 12;
    const half = Math.max(WORLD_WIDTH, WORLD_HEIGHT) * 0.62;
    const shadowCam = sun.shadow.camera;
    shadowCam.left = -half;
    shadowCam.right = half;
    shadowCam.top = half;
    shadowCam.bottom = -half;
    shadowCam.near = WORLD_WIDTH * 0.1;
    shadowCam.far = WORLD_WIDTH * 1.8;
    shadowCam.updateProjectionMatrix();
    this.scene.add(sun, sun.target);

    // ---- fill: cool sky above, warm bounce off the ground below. Keeps shadow
    // sides readable without flattening the key/fill contrast.
    this.scene.add(new THREE.HemisphereLight(SKY.top, SKY.ground, LIGHTING.fillIntensity));

    // ---- rim: a dim light from behind and opposite the key. Cheap separation -
    // it draws a bright edge down characters and furniture so they lift off the
    // surface behind them instead of merging into it.
    const rim = new THREE.DirectionalLight(LIGHTING.rimColor, LIGHTING.rimIntensity);
    rim.position.copy(centre).addScaledVector(sunDir, -WORLD_WIDTH * 0.6).setY(WORLD_WIDTH * 0.22);
    rim.target.position.copy(centre);
    this.scene.add(rim, rim.target);

    // Aerial perspective: distant geometry fades toward the horizon colour, so
    // the far house sits *behind* the near one instead of beside it.
    this.scene.fog = new THREE.Fog(SKY.horizon, WORLD_WIDTH * POST.fogNear, WORLD_WIDTH * POST.fogFar);

    // ---- post. An HDR multisampled target gives MSAA edges and lets bloom see
    // real highlight energy above 1.0; OutputPass then applies the tone map and
    // the sRGB conversion once, at the end.
    const size = new THREE.Vector2(container.clientWidth, container.clientHeight);
    const target = new THREE.WebGLRenderTarget(size.x, size.y, {
      type: THREE.HalfFloatType,
      samples: 4,
    });
    this.composer = new EffectComposer(this.renderer, target);
    this.composer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    this.composer.addPass(
      new UnrealBloomPass(size, POST.bloomStrength, POST.bloomRadius, POST.bloomThreshold)
    );
    this.composer.addPass(new OutputPass());

    window.addEventListener("resize", this.handleResize);
  }

  private handleResize = () => {
    const { clientWidth, clientHeight } = this.container;
    this.camera.aspect = clientWidth / clientHeight;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(clientWidth, clientHeight);
    this.composer.setSize(clientWidth, clientHeight);
  };

  start(onFrame?: (dt: number) => void) {
    this.onFrame = onFrame;
    this.lastTime = performance.now();
    requestAnimationFrame(this.tick);
  }

  private tick = (now: number) => {
    if (this.disposed) return;
    const dt = Math.min((now - this.lastTime) / 1000, 1 / 20);
    this.lastTime = now;
    this.onFrame?.(dt);
    this.sky.position.copy(this.camera.position);
    this.composer.render();
    requestAnimationFrame(this.tick);
  };

  dispose() {
    this.disposed = true;
    window.removeEventListener("resize", this.handleResize);
    this.composer.dispose();
    this.renderer.dispose();
    this.container.removeChild(this.renderer.domElement);
  }
}
