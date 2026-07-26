// Gamepad support via the standard Web Gamepad API, polled once per frame.
//
// This is all the code Steam Input needs: Steam presents whatever the player
// plugs in (Xbox / PlayStation / Switch Pro / Steam Deck) to the game as a
// standard gamepad, so mapping the "standard" layout here covers every
// controller without per-device work.
//
// Returns deltas in the SAME units the keyboard/mouse path produces, so
// GameController can simply add them together - a player can use stick and
// mouse in the same frame with no mode switch.

const STICK_DEADZONE = 0.22;
// Radians of camera turn per second at full stick deflection.
const LOOK_SPEED_X = 3.2;
const LOOK_SPEED_Y = 2.2;

export interface GamepadFrame {
  moveX: number; // -1..1, world-relative left/right (camera-rotated by caller)
  moveZ: number; // -1..1, forward/back
  lookX: number; // radians to add to yaw this frame
  lookY: number; // radians to add to pitch this frame
  actionPressed: boolean; // rising edge of the action button (A / cross)
  connected: boolean;
}

const EMPTY: GamepadFrame = {
  moveX: 0,
  moveZ: 0,
  lookX: 0,
  lookY: 0,
  actionPressed: false,
  connected: false,
};

function applyDeadzone(value: number): number {
  if (Math.abs(value) < STICK_DEADZONE) return 0;
  // Rescale past the deadzone so the usable range still reaches full tilt.
  const sign = Math.sign(value);
  return sign * ((Math.abs(value) - STICK_DEADZONE) / (1 - STICK_DEADZONE));
}

export class GamepadInput {
  private actionWasDown = false;

  // `dt` scales look speed so turning is frame-rate independent.
  poll(dt: number): GamepadFrame {
    const pads = navigator.getGamepads?.();
    if (!pads) return EMPTY;
    const pad = Array.from(pads).find((p): p is Gamepad => !!p && p.connected);
    if (!pad) {
      this.actionWasDown = false;
      return EMPTY;
    }

    const lx = applyDeadzone(pad.axes[0] ?? 0);
    const ly = applyDeadzone(pad.axes[1] ?? 0);
    const rx = applyDeadzone(pad.axes[2] ?? 0);
    const ry = applyDeadzone(pad.axes[3] ?? 0);

    // Standard mapping: button 0 is A / cross - the SPACE equivalent. Edge
    // detected here so a held button doesn't retrigger the action every frame.
    const actionDown = !!pad.buttons[0]?.pressed;
    const actionPressed = actionDown && !this.actionWasDown;
    this.actionWasDown = actionDown;

    return {
      moveX: lx,
      moveZ: -ly, // stick up (negative) is forward
      lookX: rx * LOOK_SPEED_X * dt,
      lookY: ry * LOOK_SPEED_Y * dt,
      actionPressed,
      connected: true,
    };
  }
}
