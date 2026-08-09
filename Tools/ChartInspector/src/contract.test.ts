import { describe, expect, it } from "vitest";
import {
  CHART_STYLE_DEFAULT,
  CHART_STYLE_RANGES,
  FIRST_STYLE_CHANGE_REVISION,
  INSPECTOR_PROTOCOL_VERSION,
  INSPECTOR_SOURCE,
  LINE_CAP_VALUES,
  LINE_JOIN_VALUES,
  MAX_INSPECTOR_REVISION,
  MIN_INSPECTOR_REVISION,
  NATIVE_SOURCE,
  NATIVE_STATE_MESSAGE,
  isChartStyle,
} from "./generated/contract";

describe("generated Chart Inspector contract", () => {
  it("preserves the canonical protocol identity", () => {
    expect({
      version: INSPECTOR_PROTOCOL_VERSION,
      minimumRevision: MIN_INSPECTOR_REVISION,
      firstStyleChangeRevision: FIRST_STYLE_CHANGE_REVISION,
      maximumRevision: MAX_INSPECTOR_REVISION,
      webSource: INSPECTOR_SOURCE,
      nativeSource: NATIVE_SOURCE,
      nativeStateMessage: NATIVE_STATE_MESSAGE,
    }).toEqual({
      version: 1,
      minimumRevision: 0,
      firstStyleChangeRevision: 1,
      maximumRevision: 1_000_000_000,
      webSource: "chart-inspector",
      nativeSource: "vercel-analytics-bar",
      nativeStateMessage: "state",
    });
  });

  it("preserves the canonical chart appearance and field constraints", () => {
    expect(CHART_STYLE_DEFAULT).toEqual({
      lineColor: "#02C06C",
      lineWidth: 1,
      lineCap: "round",
      lineJoin: "round",
      areaTopOpacity: 0.2,
      areaBottomOpacity: 0,
      chartHeight: 140,
      axisMarkCount: 3,
      yScaleHeadroom: 0.1,
      showsGridLines: true,
      showsXAxisLabels: true,
      showsYAxisLabels: true,
    });
    expect(LINE_CAP_VALUES).toEqual(["butt", "round", "square"]);
    expect(LINE_JOIN_VALUES).toEqual(["miter", "round", "bevel"]);
    expect(CHART_STYLE_RANGES).toEqual({
      lineWidth: { minimum: 0.5, maximum: 12, step: 0.5, integer: false },
      areaTopOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      areaBottomOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      chartHeight: { minimum: 80, maximum: 360, step: 1, integer: false },
      axisMarkCount: { minimum: 2, maximum: 12, step: 1, integer: true },
      yScaleHeadroom: { minimum: 0, maximum: 1, step: 0.01, integer: false },
    });
    expect(isChartStyle(CHART_STYLE_DEFAULT)).toBe(true);
  });
});
