import { DialRoot, useDialKitController } from "dialkit";
import type { ResolvedValues } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useRef, useState } from "react";
import { chartStylesAreEquivalent, createBrowserBridge } from "./bridge";
import {
  CHART_STYLE_DEFAULT,
  CHART_STYLE_RANGES,
  LINE_CAP_VALUES,
  LINE_JOIN_VALUES,
} from "./generated/contract";
import type { ChartLineCap, ChartLineJoin, ChartStyle } from "./generated/contract";

const bridge = createBrowserBridge();
const chartConfig = {
  line: {
    color: { type: "color" as const, default: CHART_STYLE_DEFAULT.lineColor },
    width: dialRange(CHART_STYLE_DEFAULT.lineWidth, CHART_STYLE_RANGES.lineWidth),
    cap: {
      type: "select" as const,
      options: [...LINE_CAP_VALUES],
      default: CHART_STYLE_DEFAULT.lineCap,
    },
    join: {
      type: "select" as const,
      options: [...LINE_JOIN_VALUES],
      default: CHART_STYLE_DEFAULT.lineJoin,
    },
  },
  area: {
    topOpacity: dialRange(CHART_STYLE_DEFAULT.areaTopOpacity, CHART_STYLE_RANGES.areaTopOpacity),
    bottomOpacity: dialRange(
      CHART_STYLE_DEFAULT.areaBottomOpacity,
      CHART_STYLE_RANGES.areaBottomOpacity,
    ),
  },
  layout: {
    height: dialRange(CHART_STYLE_DEFAULT.chartHeight, CHART_STYLE_RANGES.chartHeight),
  },
  axes: {
    markCount: dialRange(CHART_STYLE_DEFAULT.axisMarkCount, CHART_STYLE_RANGES.axisMarkCount),
    yScaleHeadroom: dialRange(
      CHART_STYLE_DEFAULT.yScaleHeadroom,
      CHART_STYLE_RANGES.yScaleHeadroom,
    ),
    gridLines: CHART_STYLE_DEFAULT.showsGridLines,
    xLabels: CHART_STYLE_DEFAULT.showsXAxisLabels,
    yLabels: CHART_STYLE_DEFAULT.showsYAxisLabels,
  },
  actions: {
    reset: { type: "action" as const, label: "Reset to defaults" },
    copyStyle: { type: "action" as const, label: "Copy canonical JSON" },
  },
};

function dialRange(
  defaultValue: number,
  range: { minimum: number; maximum: number; step: number },
): [number, number, number, number] {
  return [defaultValue, range.minimum, range.maximum, range.step];
}

export function ChartInspector() {
  const [nativeStyle, setNativeStyle] = useState<ChartStyle>();
  const suppressNextStylePost = useRef(false);
  const dial = useDialKitController("Visitors Chart", chartConfig, {
    id: "vercel-analytics-visitors-chart",
    onAction: (action) => {
      if (action === "actions.reset") {
        bridge.postReset();
      } else if (action === "actions.copyStyle") {
        bridge.postCopyStyle();
      }
    },
  });
  const setDialValues = dial.setValues;
  const getDialValues = dial.getValues;
  const values = dial.values;
  const nextStyle = useMemo(
    () => (nativeStyle === undefined ? undefined : styleFromDialValues(values)),
    [nativeStyle, values],
  );

  useEffect(() => {
    window.__chartInspectorReceiveState = (message) => bridge.receiveState(message);
    const unsubscribe = bridge.subscribe((message) => {
      const currentDialStyle = styleFromDialValues(getDialValues());
      suppressNextStylePost.current = !chartStylesAreEquivalent(currentDialStyle, message.values);
      setNativeStyle(message.values);
      setDialValues(dialValuesFromStyle(message.values));
    });
    bridge.postReady();

    return () => {
      unsubscribe();
      delete window.__chartInspectorReceiveState;
    };
  }, [getDialValues, setDialValues]);

  useEffect(() => {
    if (nextStyle !== undefined) {
      if (suppressNextStylePost.current) {
        suppressNextStylePost.current = false;
        return;
      }
      bridge.postStyleChanged(nextStyle);
    }
  }, [nextStyle]);

  return <DialRoot mode="inline" theme="system" productionEnabled />;
}

function dialValuesFromStyle(style: ChartStyle) {
  return {
    line: {
      color: style.lineColor === "accent" ? "#007AFF" : style.lineColor,
      width: style.lineWidth,
      cap: style.lineCap,
      join: style.lineJoin,
    },
    area: {
      topOpacity: style.areaTopOpacity,
      bottomOpacity: style.areaBottomOpacity,
    },
    layout: {
      height: style.chartHeight,
    },
    axes: {
      markCount: style.axisMarkCount,
      yScaleHeadroom: style.yScaleHeadroom,
      gridLines: style.showsGridLines,
      xLabels: style.showsXAxisLabels,
      yLabels: style.showsYAxisLabels,
    },
  };
}

function styleFromDialValues(values: ResolvedValues<typeof chartConfig>): ChartStyle {
  return {
    lineColor: values.line.color,
    lineWidth: values.line.width,
    lineCap: values.line.cap as ChartLineCap,
    lineJoin: values.line.join as ChartLineJoin,
    areaTopOpacity: values.area.topOpacity,
    areaBottomOpacity: values.area.bottomOpacity,
    chartHeight: values.layout.height,
    axisMarkCount: values.axes.markCount,
    yScaleHeadroom: values.axes.yScaleHeadroom,
    showsGridLines: values.axes.gridLines,
    showsXAxisLabels: values.axes.xLabels,
    showsYAxisLabels: values.axes.yLabels,
  };
}
