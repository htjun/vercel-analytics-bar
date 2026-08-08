export const INSPECTOR_PROTOCOL_VERSION = 1;
export const INSPECTOR_SOURCE = "chart-inspector";
export const NATIVE_SOURCE = "vercel-analytics-bar";
export const MAX_INSPECTOR_REVISION = 1_000_000_000;

export type ChartLineCap = "butt" | "round" | "square";
export type ChartLineJoin = "miter" | "round" | "bevel";

export interface ChartStyle {
  lineColor: string;
  lineWidth: number;
  lineCap: ChartLineCap;
  lineJoin: ChartLineJoin;
  areaTopOpacity: number;
  areaBottomOpacity: number;
  chartHeight: number;
  axisMarkCount: number;
  yScaleHeadroom: number;
  showsGridLines: boolean;
  showsXAxisLabels: boolean;
  showsYAxisLabels: boolean;
}

export interface NativeStateMessage {
  protocolVersion: number;
  type: "state";
  source: string;
  revision: number;
  values: ChartStyle;
}

export interface WebReadyMessage {
  protocolVersion: number;
  type: "ready";
  source: string;
}

export interface WebStyleChangedMessage {
  protocolVersion: number;
  type: "styleChanged";
  source: string;
  revision: number;
  values: ChartStyle;
}

export interface WebCommandMessage {
  protocolVersion: number;
  type: "reset" | "copyStyle";
  source: string;
}

type WebMessage = WebReadyMessage | WebStyleChangedMessage | WebCommandMessage;
type MessageSender = (message: WebMessage) => void;
type StateListener = (message: NativeStateMessage) => void;

export class ChartInspectorBridge {
  private currentState: NativeStateMessage | undefined;
  private lastPostedStyle: string | undefined;
  private nextRevision = 1;
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

    this.currentState = value;
    this.lastPostedStyle = undefined;
    this.nextRevision = value.revision + 1;
    this.listeners.forEach((listener) => listener(value));
    return true;
  }

  postStyleChanged(style: ChartStyle): boolean {
    if (this.currentState === undefined) {
      return false;
    }
    if (this.nextRevision > MAX_INSPECTOR_REVISION) {
      return false;
    }

    const serializedStyle = serializeStyle(style);
    if (
      chartStylesAreEquivalent(style, this.currentState.values) ||
      serializedStyle === this.lastPostedStyle
    ) {
      return false;
    }

    this.send({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: "styleChanged",
      source: INSPECTOR_SOURCE,
      revision: this.nextRevision,
      values: style,
    });
    this.nextRevision += 1;
    this.lastPostedStyle = serializedStyle;
    return true;
  }

  postReset(): void {
    this.postCommand("reset");
  }

  postCopyStyle(): void {
    this.postCommand("copyStyle");
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
    value.type === "state" &&
    value.source === NATIVE_SOURCE &&
    Number.isInteger(value.revision) &&
    typeof value.revision === "number" &&
    value.revision >= 0 &&
    value.revision <= MAX_INSPECTOR_REVISION &&
    isChartStyle(value.values)
  );
}

function isChartStyle(value: unknown): value is ChartStyle {
  if (!isRecord(value)) {
    return false;
  }

  return (
    isChartColor(value.lineColor) &&
    isNumberInRange(value.lineWidth, 0.5, 12) &&
    isOneOf(value.lineCap, ["butt", "round", "square"]) &&
    isOneOf(value.lineJoin, ["miter", "round", "bevel"]) &&
    isNumberInRange(value.areaTopOpacity, 0, 1) &&
    isNumberInRange(value.areaBottomOpacity, 0, 1) &&
    isNumberInRange(value.chartHeight, 80, 360) &&
    Number.isInteger(value.axisMarkCount) &&
    isNumberInRange(value.axisMarkCount, 2, 12) &&
    isNumberInRange(value.yScaleHeadroom, 0, 1) &&
    typeof value.showsGridLines === "boolean" &&
    typeof value.showsXAxisLabels === "boolean" &&
    typeof value.showsYAxisLabels === "boolean"
  );
}

function isChartColor(value: unknown): value is string {
  return value === "accent" || (typeof value === "string" && /^#[0-9A-F]{6}$/.test(value));
}

function isNumberInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === "number" && Number.isFinite(value) && value >= minimum && value <= maximum;
}

function isOneOf<T extends string>(value: unknown, values: readonly T[]): value is T {
  return typeof value === "string" && values.includes(value as T);
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
