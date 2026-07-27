import * as THREE from "three";

// The sky, as a real gradient instead of a flat clear colour.
//
// This is what the whole render leans on: it is drawn as the background AND
// baked into an environment map (see SceneManager), so every surface in the
// world picks up warm light from above and cool bounce from below for free.
// A flat colour gives none of that, which is most of why the old look read as
// "untextured boxes" - the materials were physically based but had nothing to
// reflect.
//
// Deliberately procedural: a few uniforms and a 20-line shader, no HDRI to
// download or ship, and the whole palette is tunable from one place.

export interface SkyColors {
  top: number;
  horizon: number;
  ground: number;
  sun: number;
}

const VERTEX = /* glsl */ `
  varying vec3 vDir;
  void main() {
    vDir = normalize(position);
    gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
  }
`;

// Two-stop vertical gradient (ground -> horizon -> zenith) with a soft sun
// bloom smeared around the light direction. `pow` on the horizon blend keeps
// the band tight so the sky reads as sky rather than as a smooth wash.
const FRAGMENT = /* glsl */ `
  uniform vec3 uTop;
  uniform vec3 uHorizon;
  uniform vec3 uGround;
  uniform vec3 uSun;
  uniform vec3 uSunDir;
  varying vec3 vDir;

  void main() {
    vec3 dir = normalize(vDir);
    float h = dir.y;
    vec3 sky = mix(uHorizon, uTop, pow(clamp(h, 0.0, 1.0), 0.45));
    vec3 below = mix(uHorizon, uGround, pow(clamp(-h, 0.0, 1.0), 0.35));
    vec3 base = h > 0.0 ? sky : below;
    float sun = pow(max(dot(dir, normalize(uSunDir)), 0.0), 220.0);
    float glow = pow(max(dot(dir, normalize(uSunDir)), 0.0), 6.0) * 0.18;
    gl_FragColor = vec4(base + uSun * (sun + glow), 1.0);
  }
`;

export function buildSkyDome(radius: number, colors: SkyColors, sunDir: THREE.Vector3): THREE.Mesh {
  const material = new THREE.ShaderMaterial({
    uniforms: {
      uTop: { value: new THREE.Color(colors.top) },
      uHorizon: { value: new THREE.Color(colors.horizon) },
      uGround: { value: new THREE.Color(colors.ground) },
      uSun: { value: new THREE.Color(colors.sun) },
      uSunDir: { value: sunDir.clone().normalize() },
    },
    vertexShader: VERTEX,
    fragmentShader: FRAGMENT,
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
  });
  const dome = new THREE.Mesh(new THREE.SphereGeometry(radius, 32, 20), material);
  dome.name = "sky";
  dome.frustumCulled = false;
  return dome;
}
