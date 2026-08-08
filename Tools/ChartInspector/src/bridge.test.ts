import { describe, expect, it } from "vitest";
import {
  ChartInspectorBridge,
  ChartStyle,
  INSPECTOR_PROTOCOL_VERSION,
  NATIVE_SOURCE,
} from "./bridge";

const defaultStyle: ChartStyle = {
  lineColor: "accent",
  lineWidth: 2,
  lineCap: "butt",
  lineJoin: "miter",
  areaTopOpacity: 0.24,
  areaBottomOpacity: 0.03,
  chartHeight: 140,
  axisMarkCount: 4,
  yScaleHeadroom: 0.1,
  showsGridLines: true,
  showsXAxisLabels: true,
  showsYAxisLabels: true,
};

describe("ChartInspectorBridge", () => {
  it("posts ready with the expected protocol identity", () => {
    const messages: unknown[] = [];
    const bridge = new ChartInspectorBridge((message) => messages.push(message));

    bridge.postReady();

    expect(messages).toEqual([
      {
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "ready",
        source: "chart-inspector",
      },
    ]);
  });

  it("does not post style before valid native hydration", () => {
    const messages: unknown[] = [];
    const bridge = new ChartInspectorBridge((message) => messages.push(message));

    expect(bridge.postStyleChanged({ ...defaultStyle, lineWidth: 3 })).toBe(false);
    expect(
      bridge.receiveState({
        protocolVersion: 2,
        type: "state",
        source: NATIVE_SOURCE,
        revision: 0,
        values: defaultStyle,
      }),
    ).toBe(false);
    expect(messages).toEqual([]);
  });

  it("hydrates, revisions, and deduplicates style changes", () => {
    const messages: unknown[] = [];
    const received: ChartStyle[] = [];
    const bridge = new ChartInspectorBridge((message) => messages.push(message));
    bridge.subscribe((message) => received.push(message.values));

    expect(
      bridge.receiveState({
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "state",
        source: NATIVE_SOURCE,
        revision: 7,
        values: defaultStyle,
      }),
    ).toBe(true);
    expect(received).toEqual([defaultStyle]);
    expect(bridge.postStyleChanged(defaultStyle)).toBe(false);

    const changedStyle = { ...defaultStyle, lineWidth: 3.5 };
    expect(bridge.postStyleChanged(changedStyle)).toBe(true);
    expect(bridge.postStyleChanged(changedStyle)).toBe(false);
    expect(messages).toEqual([
      {
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "styleChanged",
        source: "chart-inspector",
        revision: 8,
        values: changedStyle,
      },
    ]);
  });
});
