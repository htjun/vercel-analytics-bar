import { DialRoot, useDialKitController } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useRef, useState } from "react";
import { chartStylesAreEquivalent, createBrowserBridge } from "./bridge";
import type { ChartStyle } from "./generated/contract";
import {
  chartFieldConfig,
  dialValuesFromStyle,
  styleFromDialValues,
} from "./generated/inspector-adapter";

const bridge = createBrowserBridge();
export const chartConfig = {
  line: { ...chartFieldConfig.line, _collapsed: true },
  area: { ...chartFieldConfig.area, _collapsed: true },
  layout: { ...chartFieldConfig.layout, _collapsed: true },
  axes: { ...chartFieldConfig.axes, _collapsed: true },
  verticalGridLines: { ...chartFieldConfig.verticalGridLines, _collapsed: true },
  horizontalGridLines: { ...chartFieldConfig.horizontalGridLines, _collapsed: true },
  verticalAxisTicks: { ...chartFieldConfig.verticalAxisTicks, _collapsed: true },
  horizontalAxisTicks: { ...chartFieldConfig.horizontalAxisTicks, _collapsed: true },
  chartContainer: { ...chartFieldConfig.chartContainer, _collapsed: true },
  borderDash: { ...chartFieldConfig.borderDash, _collapsed: true },
  introAnimation: { ...chartFieldConfig.introAnimation, _collapsed: true },
  actions: {
    _collapsed: false,
    replayAnimation: { type: "action" as const, label: "Replay animation" },
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
      if (action === "actions.replayAnimation") {
        bridge.postReplayAnimation();
      } else if (action === "actions.reset") {
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
