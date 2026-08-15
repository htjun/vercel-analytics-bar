import { describe, expect, it } from "vitest";
import {
  CHART_STYLE_DEFAULT,
  CHART_STYLE_RANGES,
  BREAKDOWN_LIST_STYLE_DEFAULT,
  ANIMATION_EASING_VALUES,
  BORDER_STYLE_VALUES,
  FIRST_STYLE_CHANGE_REVISION,
  INSPECTOR_PROTOCOL_VERSION,
  INSPECTOR_SOURCE,
  GRID_LINE_STYLE_VALUES,
  LINE_CAP_VALUES,
  INTERPOLATION_VALUES,
  LINE_JOIN_VALUES,
  MAX_INSPECTOR_REVISION,
  MIN_INSPECTOR_REVISION,
  NATIVE_SOURCE,
  NATIVE_STATE_MESSAGE,
  isBreakdownListStyle,
  isChartStyle,
  isNativeStateMessage,
} from "./generated/contract";
import type { BreakdownListStyle, ChartStyle } from "./generated/contract";
import {
  CHART_STYLE_INSPECTOR_FIELDS,
  LIST_STYLE_INSPECTOR_FIELDS,
  chartFieldConfig,
  chartDialValuesFromStyle,
  chartStyleFromDialValues,
  listDialValuesFromStyle,
  listStyleFromDialValues,
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
      version: 7,
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
      lineColor: "#006BFF",
      lineWidth: 1.5,
      lineCap: "round",
      lineJoin: "round",
      interpolation: "monotone",
      areaTopOpacity: 0.2,
      areaBottomOpacity: 0,
      chartIntroAnimationEnabled: true,
      lineRevealDuration: 1,
      lineRevealEasing: "easeOut",
      areaFadeDuration: 1.25,
      areaFadeDelay: -0.5,
      chartHeight: 150,
      chartSidePadding: 12,
      chartVerticalPadding: 5,
      axisMarkCount: 4,
      yScaleHeadroom: 0.1,
      showsXAxisLabels: true,
      showsYAxisLabels: true,
      showsVerticalGridLines: false,
      verticalGridLineColor: "#8E8E93",
      verticalGridLineOpacity: 0.25,
      verticalGridLineWidth: 0.5,
      verticalGridLineStyle: "solid",
      showsHorizontalGridLines: true,
      horizontalGridLineColor: "#8E8E93",
      horizontalGridLineOpacity: 0.25,
      horizontalGridLineWidth: 0.5,
      horizontalGridLineStyle: "solid",
      showsVerticalAxisTicks: false,
      verticalAxisTickColor: "#8E8E93",
      verticalAxisTickOpacity: 0.5,
      verticalAxisTickWidth: 0.5,
      verticalAxisTickLength: 4,
      showsHorizontalAxisTicks: false,
      horizontalAxisTickColor: "#8E8E93",
      horizontalAxisTickOpacity: 0.5,
      horizontalAxisTickWidth: 0.5,
      horizontalAxisTickLength: 4,
      showsChartBorder: false,
      chartBorderColor: "#8E8E93",
      chartBorderOpacity: 0.27,
      chartBorderWidth: 1,
      chartBorderStyle: "dashed",
      chartBorderRadius: 10,
      chartBorderDashLength: 3,
      chartBorderDashGap: 3,
      chartBorderDashPhase: 0,
      chartBorderDashCap: "round",
    });
    expect(LINE_CAP_VALUES).toEqual(["butt", "round", "square"]);
    expect(LINE_JOIN_VALUES).toEqual(["miter", "round", "bevel"]);
    expect(INTERPOLATION_VALUES).toEqual(["linear", "monotone", "cardinal", "catmullRom"]);
    expect(GRID_LINE_STYLE_VALUES).toEqual(["solid", "dashed", "dotted"]);
    expect(BORDER_STYLE_VALUES).toEqual(["solid", "dashed"]);
    expect(ANIMATION_EASING_VALUES).toEqual(["linear", "easeIn", "easeOut", "easeInOut"]);
    expect(CHART_STYLE_RANGES).toEqual({
      lineWidth: { minimum: 0.5, maximum: 12, step: 0.5, integer: false },
      areaTopOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      areaBottomOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      lineRevealDuration: { minimum: 0.1, maximum: 3, step: 0.05, integer: false },
      areaFadeDuration: { minimum: 0.1, maximum: 2, step: 0.05, integer: false },
      areaFadeDelay: { minimum: -1, maximum: 1, step: 0.05, integer: false },
      chartHeight: { minimum: 80, maximum: 360, step: 1, integer: false },
      chartSidePadding: { minimum: 0, maximum: 64, step: 1, integer: false },
      chartVerticalPadding: { minimum: 0, maximum: 64, step: 1, integer: false },
      axisMarkCount: { minimum: 2, maximum: 12, step: 1, integer: true },
      yScaleHeadroom: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      verticalGridLineOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      verticalGridLineWidth: { minimum: 0.25, maximum: 4, step: 0.25, integer: false },
      horizontalGridLineOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      horizontalGridLineWidth: { minimum: 0.25, maximum: 4, step: 0.25, integer: false },
      verticalAxisTickOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      verticalAxisTickWidth: { minimum: 0.25, maximum: 4, step: 0.25, integer: false },
      verticalAxisTickLength: { minimum: 1, maximum: 16, step: 1, integer: false },
      horizontalAxisTickOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      horizontalAxisTickWidth: { minimum: 0.25, maximum: 4, step: 0.25, integer: false },
      horizontalAxisTickLength: { minimum: 1, maximum: 16, step: 1, integer: false },
      chartBorderOpacity: { minimum: 0, maximum: 1, step: 0.01, integer: false },
      chartBorderWidth: { minimum: 0.25, maximum: 8, step: 0.25, integer: false },
      chartBorderRadius: { minimum: 0, maximum: 64, step: 1, integer: false },
      chartBorderDashLength: { minimum: 1, maximum: 32, step: 1, integer: false },
      chartBorderDashGap: { minimum: 1, maximum: 32, step: 1, integer: false },
      chartBorderDashPhase: { minimum: 0, maximum: 64, step: 1, integer: false },
    });
    expect(isChartStyle(CHART_STYLE_DEFAULT)).toBe(true);
    expect(isChartStyle({ ...CHART_STYLE_DEFAULT, areaFadeDelay: -1 })).toBe(true);
  });

  it("generates one DialKit control for every chart field", () => {
    expect(CHART_STYLE_INSPECTOR_FIELDS).toEqual([
      { name: "lineColor", path: "line.color", control: "color" },
      { name: "lineWidth", path: "line.width", control: "range" },
      { name: "lineCap", path: "line.cap", control: "select" },
      { name: "lineJoin", path: "line.join", control: "select" },
      { name: "interpolation", path: "line.interpolation", control: "select" },
      { name: "areaTopOpacity", path: "area.topOpacity", control: "range" },
      { name: "areaBottomOpacity", path: "area.bottomOpacity", control: "range" },
      { name: "chartIntroAnimationEnabled", path: "introAnimation.enabled", control: "boolean" },
      { name: "lineRevealDuration", path: "introAnimation.lineDuration", control: "range" },
      { name: "lineRevealEasing", path: "introAnimation.lineEasing", control: "select" },
      { name: "areaFadeDuration", path: "introAnimation.fillDuration", control: "range" },
      { name: "areaFadeDelay", path: "introAnimation.fillDelay", control: "range" },
      { name: "chartHeight", path: "layout.height", control: "range" },
      { name: "chartSidePadding", path: "layout.sidePadding", control: "range" },
      { name: "chartVerticalPadding", path: "layout.topBottomPadding", control: "range" },
      { name: "axisMarkCount", path: "axes.markCount", control: "range" },
      { name: "yScaleHeadroom", path: "axes.yScaleHeadroom", control: "range" },
      { name: "showsXAxisLabels", path: "axes.xLabels", control: "boolean" },
      { name: "showsYAxisLabels", path: "axes.yLabels", control: "boolean" },
      { name: "showsVerticalGridLines", path: "verticalGridLines.visible", control: "boolean" },
      { name: "verticalGridLineColor", path: "verticalGridLines.color", control: "color" },
      { name: "verticalGridLineOpacity", path: "verticalGridLines.opacity", control: "range" },
      { name: "verticalGridLineWidth", path: "verticalGridLines.weight", control: "range" },
      { name: "verticalGridLineStyle", path: "verticalGridLines.pattern", control: "select" },
      { name: "showsHorizontalGridLines", path: "horizontalGridLines.visible", control: "boolean" },
      { name: "horizontalGridLineColor", path: "horizontalGridLines.color", control: "color" },
      { name: "horizontalGridLineOpacity", path: "horizontalGridLines.opacity", control: "range" },
      { name: "horizontalGridLineWidth", path: "horizontalGridLines.weight", control: "range" },
      { name: "horizontalGridLineStyle", path: "horizontalGridLines.pattern", control: "select" },
      { name: "showsVerticalAxisTicks", path: "verticalAxisTicks.visible", control: "boolean" },
      { name: "verticalAxisTickColor", path: "verticalAxisTicks.color", control: "color" },
      { name: "verticalAxisTickOpacity", path: "verticalAxisTicks.opacity", control: "range" },
      { name: "verticalAxisTickWidth", path: "verticalAxisTicks.weight", control: "range" },
      { name: "verticalAxisTickLength", path: "verticalAxisTicks.length", control: "range" },
      { name: "showsHorizontalAxisTicks", path: "horizontalAxisTicks.visible", control: "boolean" },
      { name: "horizontalAxisTickColor", path: "horizontalAxisTicks.color", control: "color" },
      { name: "horizontalAxisTickOpacity", path: "horizontalAxisTicks.opacity", control: "range" },
      { name: "horizontalAxisTickWidth", path: "horizontalAxisTicks.weight", control: "range" },
      { name: "horizontalAxisTickLength", path: "horizontalAxisTicks.length", control: "range" },
      { name: "showsChartBorder", path: "chartContainer.borderVisible", control: "boolean" },
      { name: "chartBorderColor", path: "chartContainer.borderColor", control: "color" },
      { name: "chartBorderOpacity", path: "chartContainer.borderOpacity", control: "range" },
      { name: "chartBorderWidth", path: "chartContainer.borderWeight", control: "range" },
      { name: "chartBorderStyle", path: "chartContainer.borderStyle", control: "select" },
      { name: "chartBorderRadius", path: "chartContainer.radius", control: "range" },
      { name: "chartBorderDashLength", path: "borderDash.length", control: "range" },
      { name: "chartBorderDashGap", path: "borderDash.gap", control: "range" },
      { name: "chartBorderDashPhase", path: "borderDash.phase", control: "range" },
      { name: "chartBorderDashCap", path: "borderDash.cap", control: "select" },
    ]);
    expect(chartFieldConfig).toEqual({
      line: {
        color: { type: "color", default: "#006BFF" },
        width: [1.5, 0.5, 12, 0.5],
        cap: { type: "select", options: ["butt", "round", "square"], default: "round" },
        join: { type: "select", options: ["miter", "round", "bevel"], default: "round" },
        interpolation: {
          type: "select",
          options: ["linear", "monotone", "cardinal", "catmullRom"],
          default: "monotone",
        },
      },
      area: {
        topOpacity: [0.2, 0, 1, 0.01],
        bottomOpacity: [0, 0, 1, 0.01],
      },
      introAnimation: {
        enabled: true,
        lineDuration: [1, 0.1, 3, 0.05],
        lineEasing: {
          type: "select",
          options: ["linear", "easeIn", "easeOut", "easeInOut"],
          default: "easeOut",
        },
        fillDuration: [1.25, 0.1, 2, 0.05],
        fillDelay: [-0.5, -1, 1, 0.05],
      },
      layout: {
        height: [150, 80, 360, 1],
        sidePadding: [12, 0, 64, 1],
        topBottomPadding: [5, 0, 64, 1],
      },
      axes: {
        markCount: [4, 2, 12, 1],
        yScaleHeadroom: [0.1, 0, 1, 0.01],
        xLabels: true,
        yLabels: true,
      },
      verticalGridLines: {
        visible: false,
        color: { type: "color", default: "#8E8E93" },
        opacity: [0.25, 0, 1, 0.01],
        weight: [0.5, 0.25, 4, 0.25],
        pattern: { type: "select", options: ["solid", "dashed", "dotted"], default: "solid" },
      },
      horizontalGridLines: {
        visible: true,
        color: { type: "color", default: "#8E8E93" },
        opacity: [0.25, 0, 1, 0.01],
        weight: [0.5, 0.25, 4, 0.25],
        pattern: { type: "select", options: ["solid", "dashed", "dotted"], default: "solid" },
      },
      verticalAxisTicks: {
        visible: false,
        color: { type: "color", default: "#8E8E93" },
        opacity: [0.5, 0, 1, 0.01],
        weight: [0.5, 0.25, 4, 0.25],
        length: [4, 1, 16, 1],
      },
      horizontalAxisTicks: {
        visible: false,
        color: { type: "color", default: "#8E8E93" },
        opacity: [0.5, 0, 1, 0.01],
        weight: [0.5, 0.25, 4, 0.25],
        length: [4, 1, 16, 1],
      },
      chartContainer: {
        borderVisible: false,
        borderColor: { type: "color", default: "#8E8E93" },
        borderOpacity: [0.27, 0, 1, 0.01],
        borderWeight: [1, 0.25, 8, 0.25],
        borderStyle: { type: "select", options: ["solid", "dashed"], default: "dashed" },
        radius: [10, 0, 64, 1],
      },
      borderDash: {
        length: [3, 1, 32, 1],
        gap: [3, 1, 32, 1],
        phase: [0, 0, 64, 1],
        cap: { type: "select", options: ["butt", "round", "square"], default: "round" },
      },
    });
  });

  it("round-trips every chart field through generated DialKit translation", () => {
    const style: ChartStyle = {
      lineColor: "#123456",
      lineWidth: 2.5,
      lineCap: "square",
      lineJoin: "bevel",
      interpolation: "catmullRom",
      areaTopOpacity: 0.45,
      areaBottomOpacity: 0.15,
      chartIntroAnimationEnabled: false,
      lineRevealDuration: 1.25,
      lineRevealEasing: "easeInOut",
      areaFadeDuration: 0.6,
      areaFadeDelay: -0.2,
      chartHeight: 220,
      chartSidePadding: 24,
      chartVerticalPadding: 12,
      axisMarkCount: 7,
      yScaleHeadroom: 0.25,
      showsXAxisLabels: false,
      showsYAxisLabels: false,
      showsVerticalGridLines: false,
      verticalGridLineColor: "#234567",
      verticalGridLineOpacity: 0.4,
      verticalGridLineWidth: 1.25,
      verticalGridLineStyle: "dashed",
      showsHorizontalGridLines: true,
      horizontalGridLineColor: "#765432",
      horizontalGridLineOpacity: 0.65,
      horizontalGridLineWidth: 2.5,
      horizontalGridLineStyle: "dotted",
      showsVerticalAxisTicks: false,
      verticalAxisTickColor: "#345678",
      verticalAxisTickOpacity: 0.35,
      verticalAxisTickWidth: 1.5,
      verticalAxisTickLength: 7,
      showsHorizontalAxisTicks: true,
      horizontalAxisTickColor: "#876543",
      horizontalAxisTickOpacity: 0.8,
      horizontalAxisTickWidth: 2.25,
      horizontalAxisTickLength: 11,
      showsChartBorder: true,
      chartBorderColor: "#987654",
      chartBorderOpacity: 0.72,
      chartBorderWidth: 3.25,
      chartBorderStyle: "dashed",
      chartBorderRadius: 28,
      chartBorderDashLength: 12,
      chartBorderDashGap: 8,
      chartBorderDashPhase: 5,
      chartBorderDashCap: "square",
    };

    expect(chartStyleFromDialValues(chartDialValuesFromStyle(style))).toEqual(style);

    const accentDialValues = chartDialValuesFromStyle({ ...style, lineColor: "accent" });
    expect(accentDialValues.line.color).toBe("#007AFF");
    expect(chartStyleFromDialValues(accentDialValues).lineColor).toBe("#007AFF");
  });

  it("validates and translates the List component contract", () => {
    const style: BreakdownListStyle = {
      ...BREAKDOWN_LIST_STYLE_DEFAULT,
      tabSpacing: 16,
      visibleRowCount: 4,
      headerToRowsSpacing: 12,
      rowHeight: 18,
      rowSpacing: 6,
      valueFontWeight: "regular",
    };

    expect(BREAKDOWN_LIST_STYLE_DEFAULT).toMatchObject({
      tabSpacing: 12,
      inactiveTabOpacity: 0.4,
      hoveredTabOpacity: 0.6,
      visibleRowCount: 5,
      headerToRowsSpacing: 16,
      rowHeight: 16,
      rowSpacing: 8,
      rowAnimationDuration: 0.22,
      rowAnimationDelay: 0.04,
    });
    expect(isBreakdownListStyle(style)).toBe(true);
    expect(isBreakdownListStyle({ ...BREAKDOWN_LIST_STYLE_DEFAULT, rowHeight: 20 })).toBe(false);
    expect(listStyleFromDialValues(listDialValuesFromStyle(style))).toEqual(style);
    expect(LIST_STYLE_INSPECTOR_FIELDS).toHaveLength(23);
    expect(isNativeStateMessage({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: NATIVE_STATE_MESSAGE,
      source: NATIVE_SOURCE,
      revision: 1,
      component: "list",
      values: style,
    })).toBe(true);
    expect(isNativeStateMessage({
      protocolVersion: INSPECTOR_PROTOCOL_VERSION,
      type: NATIVE_STATE_MESSAGE,
      source: NATIVE_SOURCE,
      revision: 1,
      component: "chart",
      values: style,
    })).toBe(false);
  });
});
