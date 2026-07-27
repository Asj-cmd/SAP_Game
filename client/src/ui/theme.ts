// The game's visual identity, in one place.
//
// Before this, the lobby was a white form card floating over a dark page while
// the in-match HUD was dark translucent glass - two different products stapled
// together. Everything the player reads now comes from the same small set of
// tokens: one surface treatment, one type scale, one accent per family, one
// elevation ramp. Screens built from shared tokens look designed; screens built
// from ad-hoc inline styles look assembled, however carefully each one is
// tuned.
//
// Injected once as a global stylesheet so both the lobby and the HUD can use
// plain class names instead of carrying long inline style strings around.

export const TEAM_B_COLOR = "#ff6b35";
export const TEAM_A_COLOR = "#2e86de";

const CSS = `
:root {
  /* Surfaces run from the page backdrop up to raised controls. Kept close
     together and very dark, so the 3D scene behind the HUD is what carries
     colour and the interface never competes with it. */
  --cg-bg-0: #0a0f16;
  --cg-bg-1: #121926;
  --cg-surface: rgba(20, 27, 38, 0.82);
  --cg-surface-raised: rgba(30, 40, 54, 0.92);
  --cg-line: rgba(255, 255, 255, 0.10);
  --cg-line-strong: rgba(255, 255, 255, 0.20);

  --cg-text: #eef3f8;
  --cg-text-dim: rgba(238, 243, 248, 0.62);
  --cg-text-faint: rgba(238, 243, 248, 0.38);

  --cg-b: ${TEAM_B_COLOR};
  --cg-a: ${TEAM_A_COLOR};
  --cg-cash: #ffc93c;
  --cg-danger: #ff5c5c;

  --cg-r-sm: 8px;
  --cg-r: 12px;
  --cg-r-lg: 18px;

  --cg-shadow: 0 10px 30px rgba(0, 0, 0, 0.45), 0 2px 6px rgba(0, 0, 0, 0.35);
  --cg-shadow-sm: 0 4px 14px rgba(0, 0, 0, 0.35);

  /* One family for everything. Tabular numerals matter more than the face:
     a timer whose digits change width jitters every second. */
  --cg-font: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
}

.cg-root, .cg-root * { font-family: var(--cg-font); box-sizing: border-box; color: var(--cg-text); }
.cg-num { font-variant-numeric: tabular-nums; }

/* --- surface -------------------------------------------------------------
   One panel treatment, used at every size. The hairline top highlight is what
   makes a translucent panel read as a physical sheet rather than as a hole
   punched in the screen. */
.cg-panel {
  background: linear-gradient(180deg, var(--cg-surface-raised), var(--cg-surface));
  border: 1px solid var(--cg-line);
  border-radius: var(--cg-r);
  box-shadow: var(--cg-shadow), inset 0 1px 0 rgba(255, 255, 255, 0.07);
  backdrop-filter: blur(14px) saturate(1.15);
  -webkit-backdrop-filter: blur(14px) saturate(1.15);
}

/* --- type ---------------------------------------------------------------- */
.cg-display {
  font-size: clamp(34px, 5.5vw, 54px);
  font-weight: 800;
  letter-spacing: -0.02em;
  line-height: 0.95;
  background: linear-gradient(180deg, #ffffff, #bcd0e4);
  -webkit-background-clip: text;
  background-clip: text;
  color: transparent;
  text-shadow: 0 6px 30px rgba(0, 0, 0, 0.55);
}
.cg-tagline { font-size: 14px; font-weight: 500; color: var(--cg-text-dim); letter-spacing: 0.01em; }
.cg-label { font-size: 10.5px; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--cg-text-faint); }
.cg-hint { font-size: 11.5px; color: var(--cg-text-dim); line-height: 1.55; }

/* --- controls ------------------------------------------------------------ */
.cg-input, .cg-select {
  width: 100%;
  padding: 11px 12px;
  font-size: 15px;
  font-weight: 500;
  color: var(--cg-text);
  background: rgba(0, 0, 0, 0.30);
  border: 1px solid var(--cg-line);
  border-radius: var(--cg-r-sm);
  outline: none;
  transition: border-color .14s ease, background .14s ease;
}
.cg-input::placeholder { color: var(--cg-text-faint); }
.cg-input:focus, .cg-select:focus { border-color: var(--cg-line-strong); background: rgba(0, 0, 0, 0.42); }
.cg-select { appearance: none; cursor: pointer; }
.cg-select option { background: var(--cg-bg-1); }

.cg-btn {
  padding: 12px 18px;
  font-size: 15px;
  font-weight: 700;
  letter-spacing: 0.01em;
  color: #fff;
  border: 0;
  border-radius: var(--cg-r-sm);
  cursor: pointer;
  background: linear-gradient(180deg, #38424f, #262e39);
  box-shadow: var(--cg-shadow-sm), inset 0 1px 0 rgba(255, 255, 255, 0.12);
  transition: transform .07s ease, filter .14s ease;
}
.cg-btn:hover { filter: brightness(1.14); }
.cg-btn:active { transform: translateY(1px); }
.cg-btn:disabled { opacity: .45; cursor: not-allowed; filter: none; transform: none; }
.cg-btn-primary { background: linear-gradient(180deg, #ff8a4f, #e2521c); }
.cg-btn-join { background: linear-gradient(180deg, #4a9ce8, #1f6fbd); }
.cg-btn-go { background: linear-gradient(180deg, #4ec96a, #2b9948); }

.cg-divider { display: flex; align-items: center; gap: 10px; color: var(--cg-text-faint); font-size: 11px; letter-spacing: .1em; }
.cg-divider::before, .cg-divider::after { content: ""; flex: 1; height: 1px; background: var(--cg-line); }

/* Team chips - the one place saturated colour is allowed in the interface. */
.cg-chip {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 3px 9px; border-radius: 999px;
  font-size: 11px; font-weight: 800; letter-spacing: .08em; text-transform: uppercase;
}
.cg-chip-b { background: rgba(255, 107, 53, .16); color: var(--cg-b); border: 1px solid rgba(255, 107, 53, .38); }
.cg-chip-a { background: rgba(46, 134, 222, .16); color: var(--cg-a); border: 1px solid rgba(46, 134, 222, .38); }

@keyframes cg-rise { from { opacity: 0; transform: translateY(10px); } to { opacity: 1; transform: none; } }
.cg-rise { animation: cg-rise .28s cubic-bezier(.2,.8,.3,1) both; }
`;

let injected = false;

export function installTheme(): void {
  if (injected) return;
  injected = true;
  const style = document.createElement("style");
  style.id = "cg-theme";
  style.textContent = CSS;
  document.head.appendChild(style);
}
