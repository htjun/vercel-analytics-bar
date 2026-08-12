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
import type { ChartStyle } from "./generated/contract";
import {
  CHART_STYLE_INSPECTOR_FIELDS,
  chartFieldConfig,
  dialValuesFromStyle,
  styleFromDialValues,
} from "./generated/inspector-adapter";

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

  it("generates one DialKit control for every chart field", () => {
    expect(CHART_STYLE_INSPECTOR_FIELDS).toEqual([
      { name: "lineColor", path: "line.color", control: "color" },
      { name: "lineWidth", path: "line.width", control: "range" },
      { name: "lineCap", path: "line.cap", control: "select" },
      { name: "lineJoin", path: "line.join", control: "select" },
      { name: "areaTopOpacity", path: "area.topOpacity", control: "range" },
      { name: "areaBottomOpacity", path: "area.bottomOpacity", control: "range" },
      { name: "chartHeight", path: "layout.height", control: "range" },
      { name: "axisMarkCount", path: "axes.markCount", control: "range" },
      { name: "yScaleHeadroom", path: "axes.yScaleHeadroom", control: "range" },
      { name: "showsGridLines", path: "axes.gridLines", control: "boolean" },
      { name: "showsXAxisLabels", path: "axes.xLabels", control: "boolean" },
      { name: "showsYAxisLabels", path: "axes.yLabels", control: "boolean" },
    ]);
    expect(chartFieldConfig).toEqual({
      line: {
        color: { type: "color", default: "#02C06C" },
        width: [1, 0.5, 12, 0.5],
        cap: { type: "select", options: ["butt", "round", "square"], default: "round" },
        join: { type: "select", options: ["miter", "round", "bevel"], default: "round" },
      },
      area: {
        topOpacity: [0.2, 0, 1, 0.01],
        bottomOpacity: [0, 0, 1, 0.01],
      },
      layout: {
        height: [140, 80, 360, 1],
      },
      axes: {
        markCount: [3, 2, 12, 1],
        yScaleHeadroom: [0.1, 0, 1, 0.01],
        gridLines: true,
        xLabels: true,
        yLabels: true,
      },
    });
  });

  it("round-trips every chart field through generated DialKit translation", () => {
    const style: ChartStyle = {
      lineColor: "#123456",
      lineWidth: 2.5,
      lineCap: "square",
      lineJoin: "bevel",
      areaTopOpacity: 0.45,
      areaBottomOpacity: 0.15,
      chartHeight: 220,
      axisMarkCount: 7,
      yScaleHeadroom: 0.25,
      showsGridLines: false,
      showsXAxisLabels: false,
      showsYAxisLabels: false,
    };

    expect(styleFromDialValues(dialValuesFromStyle(style))).toEqual(style);

    const accentDialValues = dialValuesFromStyle({ ...style, lineColor: "accent" });
    expect(accentDialValues.line.color).toBe("#007AFF");
    expect(styleFromDialValues(accentDialValues).lineColor).toBe("#007AFF");
  });
});
