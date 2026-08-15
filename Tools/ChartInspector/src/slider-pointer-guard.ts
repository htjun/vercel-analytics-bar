export const SLIDER_DRAG_THRESHOLD = 6;

interface PointerPosition {
  pointerId: number;
  clientX: number;
  clientY: number;
}

interface PointerMovement extends PointerPosition {
  buttons: number;
}

interface ActivePointer extends PointerPosition {
  isDragging: boolean;
}

export class SliderPointerGuard {
  private activePointer: ActivePointer | undefined;

  begin(position: PointerPosition): void {
    this.activePointer = { ...position, isDragging: false };
  }

  shouldBlockMove(movement: PointerMovement): boolean {
    const activePointer = this.activePointer;
    if (activePointer === undefined || activePointer.pointerId !== movement.pointerId) {
      return true;
    }
    if ((movement.buttons & 1) === 0) {
      this.activePointer = undefined;
      return true;
    }
    if (activePointer.isDragging) {
      return false;
    }

    const distance = Math.hypot(
      movement.clientX - activePointer.clientX,
      movement.clientY - activePointer.clientY,
    );
    if (distance < SLIDER_DRAG_THRESHOLD) {
      return true;
    }

    activePointer.isDragging = true;
    return false;
  }

  end(pointerId: number): void {
    if (this.activePointer?.pointerId === pointerId) {
      this.activePointer = undefined;
    }
  }
}

export function installSliderPointerGuard(document: Document): () => void {
  const guard = new SliderPointerGuard();

  const sliderFor = (event: PointerEvent): Element | null => {
    if (!(event.target instanceof Element)) return null;
    if (event.target.closest(".dialkit-slider-input, .dialkit-slider-value-editable") !== null) {
      return null;
    }
    return event.target.closest(".dialkit-slider");
  };

  const handlePointerDown = (event: PointerEvent) => {
    if (event.button !== 0 || sliderFor(event) === null) return;
    guard.begin(event);
  };
  const handlePointerMove = (event: PointerEvent) => {
    if (sliderFor(event) === null) return;
    if (guard.shouldBlockMove(event)) {
      event.stopPropagation();
    }
  };
  const handlePointerEnd = (event: PointerEvent) => {
    guard.end(event.pointerId);
  };

  document.addEventListener("pointerdown", handlePointerDown, true);
  document.addEventListener("pointermove", handlePointerMove, true);
  document.addEventListener("pointerup", handlePointerEnd, true);
  document.addEventListener("pointercancel", handlePointerEnd, true);
  document.addEventListener("lostpointercapture", handlePointerEnd, true);

  return () => {
    document.removeEventListener("pointerdown", handlePointerDown, true);
    document.removeEventListener("pointermove", handlePointerMove, true);
    document.removeEventListener("pointerup", handlePointerEnd, true);
    document.removeEventListener("pointercancel", handlePointerEnd, true);
    document.removeEventListener("lostpointercapture", handlePointerEnd, true);
  };
}
