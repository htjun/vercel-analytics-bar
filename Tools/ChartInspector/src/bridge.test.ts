import { describe, expect, it } from "vitest";
import { ChartInspectorBridge } from "./bridge";
import {
  INSPECTOR_PROTOCOL_VERSION,
  MAX_INSPECTOR_REVISION,
  NATIVE_SOURCE,
} from "./generated/contract";
import type { ChartStyle } from "./generated/contract";

const defaultStyle: ChartStyle = {
  lineColor: "accent",
  lineWidth: 2,
  lineCap: "butt",
  lineJoin: "miter",
  interpolation: "linear",
  areaTopOpacity: 0.24,
  areaBottomOpacity: 0.03,
  chartHeight: 140,
  axisMarkCount: 4,
  yScaleHeadroom: 0.1,
  showsXAxisLabels: true,
  showsYAxisLabels: true,
  showsVerticalGridLines: true,
  verticalGridLineColor: "#8E8E93",
  verticalGridLineOpacity: 0.25,
  verticalGridLineWidth: 0.5,
  verticalGridLineStyle: "solid",
  showsHorizontalGridLines: true,
  horizontalGridLineColor: "#8E8E93",
  horizontalGridLineOpacity: 0.25,
  horizontalGridLineWidth: 0.5,
  horizontalGridLineStyle: "solid",
  showsVerticalAxisTicks: true,
  verticalAxisTickColor: "#8E8E93",
  verticalAxisTickOpacity: 0.5,
  verticalAxisTickWidth: 0.5,
  verticalAxisTickLength: 4,
  showsHorizontalAxisTicks: true,
  horizontalAxisTickColor: "#8E8E93",
  horizontalAxisTickOpacity: 0.5,
  horizontalAxisTickWidth: 0.5,
  horizontalAxisTickLength: 4,
  showsChartBorder: false,
  chartBorderColor: "#8E8E93",
  chartBorderOpacity: 0.5,
  chartBorderWidth: 1,
  chartBorderStyle: "solid",
  chartBorderRadius: 16,
  chartBorderDashLength: 6,
  chartBorderDashGap: 4,
  chartBorderDashPhase: 0,
  chartBorderDashCap: "round",
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
        protocolVersion: 5,
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

  it("rejects stale and out-of-range native revisions", () => {
    const bridge = new ChartInspectorBridge(() => undefined);
    expect(
      bridge.receiveState({
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "state",
        source: NATIVE_SOURCE,
        revision: 8,
        values: defaultStyle,
      }),
    ).toBe(true);
    expect(
      bridge.receiveState({
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "state",
        source: NATIVE_SOURCE,
        revision: 7,
        values: defaultStyle,
      }),
    ).toBe(false);
    expect(
      bridge.receiveState({
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "state",
        source: NATIVE_SOURCE,
        revision: MAX_INSPECTOR_REVISION + 1,
        values: defaultStyle,
      }),
    ).toBe(false);
  });

  it("treats the displayed system accent as equivalent until edited", () => {
    const messages: unknown[] = [];
    const bridge = new ChartInspectorBridge((message) => messages.push(message));
    bridge.receiveState({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: "state",
      source: NATIVE_SOURCE,
      revision: 0,
      values: defaultStyle,
    });

    expect(bridge.postStyleChanged({ ...defaultStyle, lineColor: "#007AFF" })).toBe(false);
    expect(bridge.postStyleChanged({ ...defaultStyle, lineColor: "#FF3B30" })).toBe(true);
  });

  it("posts reset and copy only after hydration", () => {
    const messages: unknown[] = [];
    const bridge = new ChartInspectorBridge((message) => messages.push(message));

    bridge.postReset();
    bridge.postCopyStyle();
    expect(messages).toEqual([]);

    bridge.receiveState({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: "state",
      source: NATIVE_SOURCE,
      revision: 3,
      values: defaultStyle,
    });
    bridge.postReset();
    bridge.postCopyStyle();

    expect(messages).toEqual([
      {
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "reset",
        source: "chart-inspector",
      },
      {
        protocolVersion: INSPECTOR_PROTOCOL_VERSION,
        type: "copyStyle",
        source: "chart-inspector",
      },
    ]);
  });

  it("rejects an invalid native value for every style field", () => {
    const invalidValues: Partial<ChartStyle>[] = [
      { lineColor: "red" },
      { lineWidth: Number.NaN },
      { lineCap: "curved" as ChartStyle["lineCap"] },
      { lineJoin: "curved" as ChartStyle["lineJoin"] },
      { interpolation: "smooth" as ChartStyle["interpolation"] },
      { areaTopOpacity: 1.1 },
      { areaBottomOpacity: -0.1 },
      { chartHeight: 79 },
      { axisMarkCount: 4.5 },
      { yScaleHeadroom: Number.POSITIVE_INFINITY },
      { showsXAxisLabels: 1 as unknown as boolean },
      { showsYAxisLabels: null as unknown as boolean },
      { showsVerticalGridLines: "yes" as unknown as boolean },
      { verticalGridLineColor: "gray" },
      { verticalGridLineOpacity: -0.01 },
      { verticalGridLineWidth: 4.25 },
      { verticalGridLineStyle: "longDash" as ChartStyle["verticalGridLineStyle"] },
      { showsHorizontalGridLines: 1 as unknown as boolean },
      { horizontalGridLineColor: "gray" },
      { horizontalGridLineOpacity: 1.01 },
      { horizontalGridLineWidth: 0.24 },
      { horizontalGridLineStyle: "longDash" as ChartStyle["horizontalGridLineStyle"] },
      { showsVerticalAxisTicks: "yes" as unknown as boolean },
      { verticalAxisTickColor: "gray" },
      { verticalAxisTickOpacity: -0.01 },
      { verticalAxisTickWidth: 4.25 },
      { verticalAxisTickLength: 17 },
      { showsHorizontalAxisTicks: 1 as unknown as boolean },
      { horizontalAxisTickColor: "gray" },
      { horizontalAxisTickOpacity: 1.01 },
      { horizontalAxisTickWidth: 0.24 },
      { horizontalAxisTickLength: 0 },
      { showsChartBorder: "yes" as unknown as boolean },
      { chartBorderColor: "gray" },
      { chartBorderOpacity: 1.01 },
      { chartBorderWidth: 8.25 },
      { chartBorderStyle: "dotted" as ChartStyle["chartBorderStyle"] },
      { chartBorderRadius: -1 },
      { chartBorderDashLength: 0 },
      { chartBorderDashGap: 33 },
      { chartBorderDashPhase: 65 },
      { chartBorderDashCap: "curved" as ChartStyle["chartBorderDashCap"] },
    ];

    for (const invalidValue of invalidValues) {
      const bridge = new ChartInspectorBridge(() => undefined);
      expect(
        bridge.receiveState({
          protocolVersion: INSPECTOR_PROTOCOL_VERSION,
          type: "state",
          source: NATIVE_SOURCE,
          revision: 0,
          values: { ...defaultStyle, ...invalidValue },
        }),
      ).toBe(false);
    }
  });
});
