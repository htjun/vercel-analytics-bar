import {
  FIRST_STYLE_CHANGE_REVISION,
  INSPECTOR_PROTOCOL_VERSION,
  INSPECTOR_SOURCE,
  MAX_INSPECTOR_REVISION,
  MIN_INSPECTOR_REVISION,
  NATIVE_SOURCE,
  NATIVE_STATE_MESSAGE,
  isChartStyle,
} from "./generated/contract";
import type {
  ChartStyle,
  NativeStateMessage,
  WebCommandMessage,
  WebMessage,
} from "./generated/contract";

type MessageSender = (message: WebMessage) => void;
type StateListener = (message: NativeStateMessage) => void;

export class ChartInspectorBridge {
  private currentState: NativeStateMessage | undefined;
  private readonly pendingStyles = new Map<number, ChartStyle>();
  private nextRevision = FIRST_STYLE_CHANGE_REVISION;
  private readonly listeners = new Set<StateListener>();

  constructor(private readonly send: MessageSender) {}

  postReady(): void {
    this.send({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: "ready",
      source: INSPECTOR_SOURCE,
    });
  }

  receiveState(value: unknown): boolean {
    if (!isNativeStateMessage(value)) {
      return false;
    }
    if (this.currentState !== undefined && value.revision < this.currentState.revision) {
      return false;
    }

    const pendingStyle = this.pendingStyles.get(value.revision);
    const isEquivalentAcknowledgement =
      pendingStyle !== undefined && chartStylesAreEquivalent(pendingStyle, value.values);

    this.currentState = value;
    this.nextRevision = Math.max(this.nextRevision, value.revision + 1);
    for (const revision of this.pendingStyles.keys()) {
      if (revision <= value.revision) {
        this.pendingStyles.delete(revision);
      }
    }
    if (!isEquivalentAcknowledgement) {
      this.listeners.forEach((listener) => listener(value));
    }
    return true;
  }

  postStyleChanged(style: ChartStyle): boolean {
    if (this.currentState === undefined) {
      return false;
    }
    if (this.nextRevision > MAX_INSPECTOR_REVISION) {
      return false;
    }

    if (
      chartStylesAreEquivalent(style, this.currentState.values) ||
      Array.from(this.pendingStyles.values()).some((pendingStyle) =>
        chartStylesAreEquivalent(style, pendingStyle),
      )
    ) {
      return false;
    }

    const revision = this.nextRevision;
    this.send({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: "styleChanged",
      source: INSPECTOR_SOURCE,
      revision,
      values: style,
    });
    this.nextRevision += 1;
    this.pendingStyles.set(revision, { ...style });
    return true;
  }

  postReset(): void {
    this.postCommand("reset");
  }

  postCopyStyle(): void {
    this.postCommand("copyStyle");
  }

  postReplayAnimation(): void {
    this.postCommand("replayAnimation");
  }

  subscribe(listener: StateListener): () => void {
    this.listeners.add(listener);
    if (this.currentState !== undefined) {
      listener(this.currentState);
    }
    return () => this.listeners.delete(listener);
  }

  private postCommand(type: WebCommandMessage["type"]): void {
    if (this.currentState === undefined) {
      return;
    }
    this.send({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type,
      source: INSPECTOR_SOURCE,
    });
  }
}

export function createBrowserBridge(): ChartInspectorBridge {
  return new ChartInspectorBridge((message) => {
    window.webkit?.messageHandlers?.chartStyle?.postMessage(message);
  });
}

function isNativeStateMessage(value: unknown): value is NativeStateMessage {
  if (!isRecord(value)) {
    return false;
  }

  return (
    value.protocolVersion === INSPECTOR_PROTOCOL_VERSION &&
    value.type === NATIVE_STATE_MESSAGE &&
    value.source === NATIVE_SOURCE &&
    Number.isInteger(value.revision) &&
    typeof value.revision === "number" &&
    value.revision >= MIN_INSPECTOR_REVISION &&
    value.revision <= MAX_INSPECTOR_REVISION &&
    isChartStyle(value.values)
  );
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function chartStylesAreEquivalent(left: ChartStyle, right: ChartStyle): boolean {
  if (serializeStyle(left) === serializeStyle(right)) {
    return true;
  }

  const accentEquivalent = left.lineColor === "#007AFF" && right.lineColor === "accent";
  return accentEquivalent && serializeStyle({ ...left, lineColor: "accent" }) === serializeStyle(right);
}

function serializeStyle(style: ChartStyle): string {
  return JSON.stringify(style);
}

declare global {
  interface Window {
    __chartInspectorReceiveState?: (message: unknown) => void;
    webkit?: {
      messageHandlers?: {
        chartStyle?: {
          postMessage: (message: WebMessage) => void;
        };
      };
    };
  }
}
