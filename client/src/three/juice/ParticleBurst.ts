import * as THREE from "three";

// Cheap one-shot particle bursts (cash sparkle on a deposit, red sparks on a
// jail). One THREE.Points object with a fixed pool of vertices - no per-burst
// allocation, no geometry churn, one draw call for the whole system.
//
// Purely cosmetic and purely client-side: it reads game events and draws, and
// nothing here can affect simulation state.

const MAX_PARTICLES = 240;
const GRAVITY = 900;
const DRAG = 1.6;

interface Particle {
  life: number; // seconds remaining
  maxLife: number;
  vx: number;
  vy: number;
  vz: number;
}

export class ParticleBurst {
  private points: THREE.Points;
  private positions: Float32Array;
  private colors: Float32Array;
  private sizes: Float32Array;
  private pool: Particle[] = [];
  private next = 0;

  constructor(scene: THREE.Scene) {
    this.positions = new Float32Array(MAX_PARTICLES * 3);
    this.colors = new Float32Array(MAX_PARTICLES * 3);
    this.sizes = new Float32Array(MAX_PARTICLES);
    for (let i = 0; i < MAX_PARTICLES; i++) {
      this.pool.push({ life: 0, maxLife: 1, vx: 0, vy: 0, vz: 0 });
      this.sizes[i] = 0;
    }

    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute("position", new THREE.BufferAttribute(this.positions, 3));
    geometry.setAttribute("color", new THREE.BufferAttribute(this.colors, 3));
    geometry.setAttribute("size", new THREE.BufferAttribute(this.sizes, 1));

    // Additive, depth-tested but not depth-written, so sparks glow over the
    // scene without punching holes in each other.
    const material = new THREE.PointsMaterial({
      size: 9,
      vertexColors: true,
      transparent: true,
      opacity: 0.95,
      depthWrite: false,
      blending: THREE.AdditiveBlending,
      sizeAttenuation: true,
    });

    this.points = new THREE.Points(geometry, material);
    this.points.frustumCulled = false;
    scene.add(this.points);
  }

  // Fire `count` particles from a point. Oldest particles are recycled first, so
  // a burst during a busy moment degrades gracefully instead of allocating.
  burst(x: number, y: number, z: number, colorHex: number, count = 24, speed = 260) {
    const color = new THREE.Color(colorHex);
    for (let i = 0; i < count; i++) {
      const idx = this.next;
      this.next = (this.next + 1) % MAX_PARTICLES;
      const p = this.pool[idx];
      p.maxLife = 0.5 + Math.random() * 0.45;
      p.life = p.maxLife;
      // Upward-biased cone so bursts read as a "pop" rather than a sphere.
      const angle = Math.random() * Math.PI * 2;
      const spread = 0.35 + Math.random() * 0.75;
      const mag = speed * (0.45 + Math.random() * 0.75);
      p.vx = Math.cos(angle) * spread * mag;
      p.vz = Math.sin(angle) * spread * mag;
      p.vy = mag * (0.7 + Math.random() * 0.6);
      this.positions[idx * 3] = x;
      this.positions[idx * 3 + 1] = y;
      this.positions[idx * 3 + 2] = z;
      this.colors[idx * 3] = color.r;
      this.colors[idx * 3 + 1] = color.g;
      this.colors[idx * 3 + 2] = color.b;
      this.sizes[idx] = 1;
    }
  }

  update(dt: number) {
    let anyAlive = false;
    for (let i = 0; i < MAX_PARTICLES; i++) {
      const p = this.pool[i];
      if (p.life <= 0) continue;
      anyAlive = true;
      p.life -= dt;
      if (p.life <= 0) {
        this.sizes[i] = 0;
        continue;
      }
      const drag = 1 - Math.min(1, DRAG * dt);
      p.vx *= drag;
      p.vz *= drag;
      p.vy = p.vy * drag - GRAVITY * dt;
      this.positions[i * 3] += p.vx * dt;
      this.positions[i * 3 + 1] += p.vy * dt;
      this.positions[i * 3 + 2] += p.vz * dt;
      // Fade by shrinking - PointsMaterial has no per-vertex alpha.
      this.sizes[i] = Math.max(0, p.life / p.maxLife);
    }
    this.points.visible = anyAlive;
    if (!anyAlive) return;
    const geo = this.points.geometry;
    (geo.getAttribute("position") as THREE.BufferAttribute).needsUpdate = true;
    (geo.getAttribute("color") as THREE.BufferAttribute).needsUpdate = true;
    // Scale the shared point size by the largest surviving particle so bursts
    // visibly shrink as they die.
    let maxSize = 0;
    for (let i = 0; i < MAX_PARTICLES; i++) maxSize = Math.max(maxSize, this.sizes[i]);
    (this.points.material as THREE.PointsMaterial).size = 9 * maxSize;
  }

  dispose() {
    this.points.geometry.dispose();
    (this.points.material as THREE.Material).dispose();
    this.points.parent?.remove(this.points);
  }
}
