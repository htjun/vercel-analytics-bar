import { DialRoot, useDialKitController } from "dialkit";
import type { ResolvedValues } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  ChartLineCap,
  ChartLineJoin,
  ChartStyle,
  chartStylesAreEquivalent,
  createBrowserBridge,
} from "./bridge";

const bridge = createBrowserBridge();
const chartConfig = {
  line: {
    color: { type: "color" as const, default: "#007AFF" },
    width: [2, 0.5, 12, 0.5] as [number, number, number, number],
    cap: {
      type: "select" as const,
      options: ["butt", "round", "square"],
      default: "butt",
    },
    join: {
      type: "select" as const,
      options: ["miter", "round", "bevel"],
      default: "miter",
    },
  },
  area: {
    topOpacity: [0.24, 0, 1, 0.01] as [number, number, number, number],
    bottomOpacity: [0.03, 0, 1, 0.01] as [number, number, number, number],
  },
  layout: {
    height: [140, 80, 360, 1] as [number, number, number, number],
  },
  axes: {
    markCount: [4, 2, 12, 1] as [number, number, number, number],
    yScaleHeadroom: [0.1, 0, 1, 0.01] as [number, number, number, number],
    gridLines: true,
    xLabels: true,
    yLabels: true,
  },
  actions: {
    reset: { type: "action" as const, label: "Reset to defaults" },
    copyStyle: { type: "action" as const, label: "Copy canonical JSON" },
  },
};

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
