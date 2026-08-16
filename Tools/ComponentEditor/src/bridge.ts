import {
  FIRST_STYLE_CHANGE_REVISION,
  EDITOR_PROTOCOL_VERSION,
  EDITOR_SOURCE,
  MAX_EDITOR_REVISION,
  isNativeStateMessage,
} from "./generated/contract";
import type {
  BreakdownListStyle,
  ChartStyle,
  NumberStyle,
  NativeStateMessage,
  WebCommandMessage,
  WebMessage,
} from "./generated/contract";

type MessageSender = (message: WebMessage) => void;
type StateListener = (message: NativeStateMessage) => void;
export type ComponentStyleChange =
  | { component: "chart"; values: ChartStyle }
  | { component: "list"; values: BreakdownListStyle }
  | { component: "numbers"; values: NumberStyle };

export class ComponentEditorBridge {
  private currentState: NativeStateMessage | undefined;
  private readonly pendingStyles = new Map<number, ComponentStyleChange>();
  private nextRevision = FIRST_STYLE_CHANGE_REVISION;
  private readonly listeners = new Set<StateListener>();

  constructor(private readonly send: MessageSender) {}

  postReady(): void {
    this.send({
      protocolVersion: EDITOR_PROTOCOL_VERSION,
      type: "ready",
      source: EDITOR_SOURCE,
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
      pendingStyle !== undefined && componentStyleMatches(value, pendingStyle);

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

  postStyleChanged(changeOrChartStyle: ComponentStyleChange | ChartStyle): boolean {
    if (this.currentState === undefined) {
      return false;
    }
    const change: ComponentStyleChange = "component" in changeOrChartStyle
      ? changeOrChartStyle
      : { component: "chart", values: changeOrChartStyle };
    if (this.currentState.component !== change.component) {
      return false;
    }
    if (this.nextRevision > MAX_EDITOR_REVISION) {
      return false;
    }

    const latestPendingStyle = this.pendingStyles.get(this.nextRevision - 1);
    if (
      componentStyleMatches(this.currentState, change) ||
      (latestPendingStyle !== undefined && componentChangesAreEquivalent(change, latestPendingStyle))
    ) {
      return false;
    }

    const revision = this.nextRevision;
    switch (change.component) {
      case "chart":
        this.send({
          protocolVersion: EDITOR_PROTOCOL_VERSION,
          type: "styleChanged",
          source: EDITOR_SOURCE,
          revision,
          component: change.component,
          values: change.values,
        });
        break;
      case "list":
        this.send({
          protocolVersion: EDITOR_PROTOCOL_VERSION,
          type: "styleChanged",
          source: EDITOR_SOURCE,
          revision,
          component: change.component,
          values: change.values,
        });
        break;
      case "numbers":
        this.send({
          protocolVersion: EDITOR_PROTOCOL_VERSION,
          type: "styleChanged",
          source: EDITOR_SOURCE,
          revision,
          component: change.component,
          values: change.values,
        });
        break;
    }
    this.nextRevision += 1;
    this.pendingStyles.set(revision, change);
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

  postNumberPreviewValue(testValue: string): boolean {
    const currentState = this.currentState;
    if (currentState?.component !== "numbers" || currentState.testValue === testValue) {
      return false;
    }
    this.currentState = { ...currentState, testValue };
    this.send({
      protocolVersion: EDITOR_PROTOCOL_VERSION,
      type: "numberPreviewValueChanged",
      source: EDITOR_SOURCE,
      component: "numbers",
      testValue,
    });
    return true;
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
      protocolVersion: EDITOR_PROTOCOL_VERSION,
      type,
      source: EDITOR_SOURCE,
      component: this.currentState.component,
    });
  }
}

export function createBrowserBridge(): ComponentEditorBridge {
  return new ComponentEditorBridge((message) => {
    window.webkit?.messageHandlers?.chartStyle?.postMessage(message);
  });
}

export function chartStylesAreEquivalent(left: ChartStyle, right: ChartStyle): boolean {
  if (serializeStyle(left) === serializeStyle(right)) {
    return true;
  }

  const normalizedLeft = left.lineColor === "#007AFF" ? { ...left, lineColor: "accent" } : left;
  const normalizedRight = right.lineColor === "#007AFF" ? { ...right, lineColor: "accent" } : right;
  return serializeStyle(normalizedLeft) === serializeStyle(normalizedRight);
}

export function listStylesAreEquivalent(left: BreakdownListStyle, right: BreakdownListStyle): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

export function numberStylesAreEquivalent(left: NumberStyle, right: NumberStyle): boolean {
  return JSON.stringify(left) === JSON.stringify(right);
}

function componentStyleMatches(state: NativeStateMessage, change: ComponentStyleChange): boolean {
  if (state.component !== change.component) {
    return false;
  }
  if (state.component === "chart" && change.component === "chart") {
    return chartStylesAreEquivalent(state.values, change.values);
  }
  if (state.component === "list" && change.component === "list") {
    return listStylesAreEquivalent(state.values, change.values);
  }
  if (state.component === "numbers" && change.component === "numbers") {
    return numberStylesAreEquivalent(state.values, change.values);
  }
  return false;
}

function componentChangesAreEquivalent(
  left: ComponentStyleChange,
  right: ComponentStyleChange,
): boolean {
  if (left.component !== right.component) {
    return false;
  }
  if (left.component === "chart" && right.component === "chart") {
    return chartStylesAreEquivalent(left.values, right.values);
  }
  if (left.component === "list" && right.component === "list") {
    return listStylesAreEquivalent(left.values, right.values);
  }
  if (left.component === "numbers" && right.component === "numbers") {
    return numberStylesAreEquivalent(left.values, right.values);
  }
  return false;
}

function serializeStyle(style: ChartStyle): string {
  return JSON.stringify(style);
}

declare global {
  interface Window {
    __componentEditorReceiveState?: (message: unknown) => void;
    webkit?: {
      messageHandlers?: {
        chartStyle?: {
          postMessage: (message: WebMessage) => void;
        };
      };
    };
  }
}
