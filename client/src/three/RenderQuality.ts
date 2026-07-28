// Render quality tiers, and a controller that picks one by MEASURING.
//
// The post stack this game grew - MSAA HDR target, full-resolution ambient
// occlusion, bloom, a 4096 shadow map - was sized for a discrete GPU and had no
// way to turn down. On a laptop at devicePixelRatio 2 that is roughly twenty
// full-screen passes over 4.6 megapixels to draw a scene of 55,000 triangles:
// the geometry is free and the pixels are the entire cost.
//
// The honest fix is not a better guess at a default. Browsers no longer report
// the GPU reliably (WEBGL_debug_renderer_info is masked in most of them), so any
// static default is wrong for somebody. This starts at a middle setting, watches
// how long frames actually take, and steps down until they fit the budget - or
// up, if there is headroom going spare. The player can also just pick a tier and
// have it remembered.
//
// Ordered cheapest first. `next`/`previous` walk this array.
export const TIER_ORDER = ["low", "medium", "high"] as const;
export type QualityTier = (typeof TIER_ORDER)[number];

export interface QualitySettings {
  /** Ceiling on devicePixelRatio. Every post pass costs this SQUARED. */
  maxPixelRatio: number;
  /** Ambient occlusion: renders the scene twice more (depth + normals) and a
   *  full-resolution AO + blur on top. By far the most expensive single item. */
  ssao: boolean;
  /** Bloom: ~10 blur passes, already half-resolution internally. Mid-priced. */
  bloom: boolean;
  /** Multisampling on the HDR target, read once at startup (see note below).
   *  Kept generous even on the cheap tiers: the stair flights are the highest
   *  frequency geometry in the game - twelve light treads against dark beams -
   *  and undersampled edges there crawl badly in motion. MSAA is a fraction of
   *  what ambient occlusion costs, so it is the wrong place to economise. */
  msaaSamples: number;
  shadowMapSize: number;
  /** PCF-soft looks better but samples a fixed wide kernel and ignores
   *  `shadow.radius`; plain PCF is cheaper AND lets the radius blur work. */
  softShadows: boolean;
}

export const TIERS: Record<QualityTier, QualitySettings> = {
  low: { maxPixelRatio: 1, ssao: false, bloom: false, msaaSamples: 2, shadowMapSize: 1024, softShadows: false },
  medium: { maxPixelRatio: 1.25, ssao: false, bloom: true, msaaSamples: 4, shadowMapSize: 2048, softShadows: false },
  high: { maxPixelRatio: 2, ssao: true, bloom: true, msaaSamples: 4, shadowMapSize: 4096, softShadows: true },
};

const STORAGE_KEY = "cg-quality";

// MSAA sample count is fixed when the render target is created, so a tier
// change mid-session applies every other setting immediately and picks up the
// sample count on the next load. Persisting the tier is what makes that work.
//
// HOW the tier was reached is stored alongside it, and matters: a tier the
// player picked must be honoured forever, but one the measurement arrived at is
// only ever a guess about a machine whose load can change. Storing just the tier
// would make the first automatic adjustment look like a player decision on the
// next load, and adaptation would switch itself off permanently.
export interface StoredTier {
  tier: QualityTier;
  manual: boolean;
}

export function loadTier(): StoredTier | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const [origin, tier] = raw.split(":");
    if (!TIER_ORDER.includes(tier as QualityTier)) return null;
    return { tier: tier as QualityTier, manual: origin === "manual" };
  } catch {
    return null; // private browsing / storage disabled
  }
}

export function saveTier(tier: QualityTier, manual: boolean): void {
  try {
    localStorage.setItem(STORAGE_KEY, `${manual ? "manual" : "auto"}:${tier}`);
  } catch {
    /* not worth failing a frame over */
  }
}

// Budgets in milliseconds per frame. Stepping down at 60fps-with-headroom would
// make the game flicker between tiers on a machine sitting near the line, so the
// two thresholds are deliberately far apart: drop only when clearly missing 30
// fps, raise only when clearly beating 60.
const DROP_ABOVE_MS = 27;
const RAISE_BELOW_MS = 11;
const WINDOW = 45; // frames per decision - about three quarters of a second
const SETTLE_FRAMES = 30; // ignored after a change, while caches warm up

export class AdaptiveQuality {
  private samples: number[] = [];
  private settle = SETTLE_FRAMES;
  private raised = false; // only ever step UP once, to stop hunting
  /** True once the player has chosen a tier by hand - adaptation then stops. */
  private manual: boolean;

  constructor(
    private tier: QualityTier,
    private readonly onChange: (tier: QualityTier) => void,
    manual: boolean
  ) {
    this.manual = manual;
  }

  get current(): QualityTier {
    return this.tier;
  }

  /** Called by the player picking a tier. Adaptation stops for the session. */
  setManual(tier: QualityTier): void {
    this.manual = true;
    this.tier = tier;
    saveTier(tier, true);
    this.onChange(tier);
  }

  /** One frame's duration, in milliseconds. */
  sample(frameMs: number): void {
    if (this.manual) return;
    if (this.settle > 0) {
      this.settle--;
      return;
    }
    this.samples.push(frameMs);
    if (this.samples.length < WINDOW) return;

    // The MEDIAN, not the mean: a single 300ms hitch from a texture upload or a
    // garbage collection should not drop everyone a tier.
    const sorted = [...this.samples].sort((a, b) => a - b);
    const median = sorted[sorted.length >> 1];
    this.samples = [];

    const index = TIER_ORDER.indexOf(this.tier);
    if (median > DROP_ABOVE_MS && index > 0) {
      this.apply(TIER_ORDER[index - 1]);
    } else if (median < RAISE_BELOW_MS && index < TIER_ORDER.length - 1 && !this.raised) {
      this.raised = true;
      this.apply(TIER_ORDER[index + 1]);
    }
  }

  private apply(tier: QualityTier): void {
    this.tier = tier;
    this.settle = SETTLE_FRAMES;
    saveTier(tier, false);
    this.onChange(tier);
  }
}
