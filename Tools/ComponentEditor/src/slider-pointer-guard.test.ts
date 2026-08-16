import { describe, expect, it } from "vitest";
import { SLIDER_DRAG_THRESHOLD, SliderPointerGuard } from "./slider-pointer-guard";

const pointer = (overrides: Partial<Parameters<SliderPointerGuard["begin"]>[0]> = {}) => ({
  pointerId: 1,
  clientX: 100,
  clientY: 50,
  ...overrides,
});

const movement = (
  overrides: Partial<Parameters<SliderPointerGuard["shouldBlockMove"]>[0]> = {},
) => ({
  ...pointer(),
  buttons: 1,
  ...overrides,
});

describe("SliderPointerGuard", () => {
  it("keeps incidental movement as a click", () => {
    const guard = new SliderPointerGuard();
    guard.begin(pointer());

    expect(
      guard.shouldBlockMove(movement({ clientX: 100 + SLIDER_DRAG_THRESHOLD - 0.1 })),
    ).toBe(true);
  });

  it("forwards a deliberate held drag after the threshold is crossed", () => {
    const guard = new SliderPointerGuard();
    guard.begin(pointer());

    expect(guard.shouldBlockMove(movement({ clientX: 100 + SLIDER_DRAG_THRESHOLD }))).toBe(false);
    expect(guard.shouldBlockMove(movement({ clientX: 101 }))).toBe(false);
  });

  it("blocks movement as soon as the primary button is released", () => {
    const guard = new SliderPointerGuard();
    guard.begin(pointer());
    expect(guard.shouldBlockMove(movement({ clientX: 110 }))).toBe(false);

    expect(guard.shouldBlockMove(movement({ clientX: 120, buttons: 0 }))).toBe(true);
    expect(guard.shouldBlockMove(movement({ clientX: 130 }))).toBe(true);
  });

  it("ends the gesture on pointer up, cancellation, or lost capture", () => {
    for (const pointerId of [1, 2, 3]) {
      const guard = new SliderPointerGuard();
      guard.begin(pointer({ pointerId }));
      guard.end(pointerId);

      expect(guard.shouldBlockMove(movement({ pointerId, clientX: 120 }))).toBe(true);
    }
  });

  it("never forwards movement from a different pointer", () => {
    const guard = new SliderPointerGuard();
    guard.begin(pointer());

    expect(guard.shouldBlockMove(movement({ pointerId: 2, clientX: 120 }))).toBe(true);
  });
});
