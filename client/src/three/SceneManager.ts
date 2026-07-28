import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { SSAOPass } from "three/addons/postprocessing/SSAOPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { WORLD_WIDTH, WORLD_HEIGHT, SKY, LIGHTING, POST } from "../constants";
import { buildSkyDome } from "./world/SkyDome";
import { AdaptiveQuality, TIERS, TIER_ORDER, loadTier, type QualityTier } from "./RenderQuality";

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
  private container: HTMLElement;
  private onFrame?: (dt: number) => void;
  private lastTime = performance.now();
  private disposed = false;

  // Post passes are held so quality changes can switch them off without
  // rebuilding the composer - the expensive ones are exactly the optional ones.
  private ssaoPass!: SSAOPass;
  private bloomPass!: UnrealBloomPass;
  private sun!: THREE.DirectionalLight;
  private readonly quality: AdaptiveQuality;
  /** Fires whenever the tier changes, so the HUD can say so. */
  onQualityChange?: (tier: QualityTier) => void;

  constructor(container: HTMLElement) {
    this.container = container;
    const stored = loadTier();
    // Nothing stored means no evidence about this machine: start in the middle
    // and let AdaptiveQuality find the right tier from measured frames. A
    // remembered AUTO tier is a better starting guess but still open to
    // revision; only a tier the player chose pins adaptation off.
    const startTier: QualityTier = stored?.tier ?? "medium";

    // Far clip derives from WORLD_WIDTH so the whole map stays inside the
    // frustum at any WORLD_SCALE. Near is deliberately not 0.1: depth precision
    // is a ratio, and a tight near plane is what makes distant coplanar
    // surfaces fight.
    this.camera = new THREE.PerspectiveCamera(58, container.clientWidth / container.clientHeight, 4, WORLD_WIDTH * 2.2);
    this.camera.position.set(WORLD_WIDTH / 2, WORLD_WIDTH * 0.35, WORLD_HEIGHT * 1.4);
    this.camera.lookAt(WORLD_WIDTH / 2, 0, WORLD_HEIGHT / 2);

    // `antialias` is deliberately OFF. Everything is drawn through the
    // composer's own multisampled target, so the renderer's antialiased back
    // buffer was a second full-size MSAA surface that was allocated, resolved
    // and never looked at.
    this.renderer = new THREE.WebGLRenderer({ antialias: false, powerPreference: "high-performance" });
    this.renderer.setSize(container.clientWidth, container.clientHeight);
    this.renderer.shadowMap.enabled = true;
    // PCF rather than VSM: VSM's variance filter over a frustum this large
    // washed every shadow out completely, and it light-leaks through the thin
    // geometry (sills, treads, trim) this world is full of. Soft-PCF is the
    // top tier only - it samples a wide fixed kernel per fragment.
    this.renderer.shadowMap.type = THREE.PCFShadowMap;
    this.renderer.toneMapping = THREE.ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = LIGHTING.exposure;
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    container.appendChild(this.renderer.domElement);

    // ---- sun direction drives the sky, the key light and the shadows, so all
    // three always agree about where the light is coming from.
    const sunDir = new THREE.Vector3(...LIGHTING.sunDirection).normalize();

    // The sky is baked ONCE into a cube texture and used as the background,
    // rather than being a dome mesh in the scene. A dome is geometry: it lands
    // in the depth buffer, and the ambient-occlusion pass then sees a surface
    // wrapped around the camera and darkens the whole frame against it. Baking
    // it means the sky costs no geometry, cannot be clipped by the far plane,
    // and is invisible to every pass that reasons about depth.
    const envScene = new THREE.Scene();
    envScene.add(buildSkyDome(50, SKY, sunDir));
    const cubeTarget = new THREE.WebGLCubeRenderTarget(512);
    const cubeCam = new THREE.CubeCamera(1, 200, cubeTarget);
    cubeCam.update(this.renderer, envScene);
    this.scene.background = cubeTarget.texture;

    // ---- image-based lighting, from that same sky.
    const pmrem = new THREE.PMREMGenerator(this.renderer);
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
    sun.shadow.bias = -0.0008;
    sun.shadow.normalBias = 1.2;
    sun.shadow.radius = LIGHTING.shadowSoftness;
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
    this.sun = sun;

    // ---- fill: cool sky above, warm bounce off the ground below. Keeps shadow
    // sides readable without flattening the key/fill contrast.
    this.scene.add(new THREE.HemisphereLight(LIGHTING.fillSky, LIGHTING.fillGround, LIGHTING.fillIntensity));

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
      samples: TIERS[startTier].msaaSamples,
    });
    this.composer = new EffectComposer(this.renderer, target);
    this.composer.addPass(new RenderPass(this.scene, this.camera));
    // Ambient occlusion. Sun shadows describe the big forms; AO describes the
    // small ones - where a skirting meets a floor, where a step meets its
    // stringer, where furniture sits on a rug. Without it every contact is a
    // hard edge with no darkening and the room reads as parts floating next to
    // each other rather than parts touching.
    this.ssaoPass = new SSAOPass(this.scene, this.camera, size.x, size.y);
    this.ssaoPass.kernelRadius = POST.aoRadius;
    this.ssaoPass.minDistance = POST.aoMinDistance;
    this.ssaoPass.maxDistance = POST.aoMaxDistance;
    this.composer.addPass(this.ssaoPass);
    this.bloomPass = new UnrealBloomPass(size, POST.bloomStrength, POST.bloomRadius, POST.bloomThreshold);
    this.composer.addPass(this.bloomPass);
    this.composer.addPass(new OutputPass());

    this.quality = new AdaptiveQuality(startTier, (tier) => this.applyQuality(tier), stored?.manual ?? false);
    this.applyQuality(startTier);

    window.addEventListener("resize", this.handleResize);
  }

  /** Everything a tier controls except the MSAA sample count, which is baked
   *  into the render target and therefore only changes on the next load. */
  private applyQuality(tier: QualityTier): void {
    const q = TIERS[tier];
    const ratio = Math.min(window.devicePixelRatio, q.maxPixelRatio);
    this.renderer.setPixelRatio(ratio);
    this.composer.setPixelRatio(ratio);
    this.ssaoPass.enabled = q.ssao;
    this.bloomPass.enabled = q.bloom;
    this.renderer.shadowMap.type = q.softShadows ? THREE.PCFSoftShadowMap : THREE.PCFShadowMap;
    // Soft-PCF samples its own fixed kernel and ignores `radius`; plain PCF is
    // where the configured softness actually does something.
    this.sun.shadow.radius = q.softShadows ? 1 : LIGHTING.shadowSoftness;
    if (this.sun.shadow.mapSize.width !== q.shadowMapSize) {
      this.sun.shadow.mapSize.set(q.shadowMapSize, q.shadowMapSize);
      // The map is allocated at the old size; dropping it forces a rebuild.
      this.sun.shadow.map?.dispose();
      this.sun.shadow.map = null;
    }
    this.renderer.shadowMap.needsUpdate = true;
    this.onQualityChange?.(tier);
  }

  get qualityTier(): QualityTier {
    return this.quality.current;
  }

  /** Step to the next tier, wrapping. Also pins the tier: once the player has
   *  an opinion, the adaptive controller stops overriding it. */
  cycleQuality(): QualityTier {
    const next = TIER_ORDER[(TIER_ORDER.indexOf(this.quality.current) + 1) % TIER_ORDER.length];
    this.quality.setManual(next);
    return next;
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
    const elapsed = now - this.lastTime;
    const dt = Math.min(elapsed / 1000, 1 / 20);
    this.lastTime = now;
    this.onFrame?.(dt);
    this.composer.render();
    // Wall-clock frame interval, which is what the player experiences - a
    // GPU-time query would miss stalls in the browser's own compositor.
    this.quality.sample(elapsed);
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
