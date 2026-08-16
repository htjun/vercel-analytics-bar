import { DialRoot, useDialKitController } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  chartStylesAreEquivalent,
  createBrowserBridge,
  listStylesAreEquivalent,
} from "./bridge";
import type {
  BreakdownListStyle,
  ChartStyle,
  NativeStateMessage,
} from "./generated/contract";
import {
  chartFieldConfig,
  chartDialValuesFromStyle,
  chartStyleFromDialValues,
  listDialValuesFromStyle,
  listFieldConfig,
  listStyleFromDialValues,
} from "./generated/component-editor-adapter";

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

export const listConfig = {
  tabs: { ...listFieldConfig.tabs, _collapsed: true },
  rows: { ...listFieldConfig.rows, _collapsed: true },
  layout: { ...listFieldConfig.layout, _collapsed: true },
  label: { ...listFieldConfig.label, _collapsed: true },
  value: { ...listFieldConfig.value, _collapsed: true },
  emptyState: { ...listFieldConfig.emptyState, _collapsed: true },
  introAnimation: { ...listFieldConfig.introAnimation, _collapsed: true },
  actions: {
    _collapsed: false,
    replayAnimation: { type: "action" as const, label: "Replay intro animation" },
    reset: { type: "action" as const, label: "Reset to defaults" },
    copyStyle: { type: "action" as const, label: "Copy canonical JSON" },
  },
};

export function ComponentEditor() {
  const [nativeState, setNativeState] = useState<NativeStateMessage>();

  useEffect(() => {
    window.__componentEditorReceiveState = (message) => bridge.receiveState(message);
    const unsubscribe = bridge.subscribe(setNativeState);
    bridge.postReady();

    return () => {
      unsubscribe();
      delete window.__componentEditorReceiveState;
    };
  }, []);

  return (
    <>
      {nativeState?.component === "chart" && <ChartControls style={nativeState.values} />}
      {nativeState?.component === "list" && <ListControls style={nativeState.values} />}
      <DialRoot mode="inline" theme="system" productionEnabled />
    </>
  );
}

function ChartControls({ style }: { style: ChartStyle }) {
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
  const nextStyle = useMemo(() => chartStyleFromDialValues(values), [values]);

  useEffect(() => {
    const currentDialStyle = chartStyleFromDialValues(getDialValues());
    suppressNextStylePost.current = !chartStylesAreEquivalent(currentDialStyle, style);
    setDialValues(chartDialValuesFromStyle(style));
  }, [getDialValues, setDialValues, style]);

  useEffect(() => {
    if (suppressNextStylePost.current) {
      suppressNextStylePost.current = false;
      return;
    }
    bridge.postStyleChanged({ component: "chart", values: nextStyle });
  }, [nextStyle]);

  return null;
}

function ListControls({ style }: { style: BreakdownListStyle }) {
  const suppressNextStylePost = useRef(false);
  const dial = useDialKitController("Breakdown List", listConfig, {
    id: "vercel-analytics-breakdown-list",
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
  const nextStyle = useMemo(() => listStyleFromDialValues(values), [values]);

  useEffect(() => {
    const currentDialStyle = listStyleFromDialValues(getDialValues());
    suppressNextStylePost.current = !listStylesAreEquivalent(currentDialStyle, style);
    setDialValues(listDialValuesFromStyle(style));
  }, [getDialValues, setDialValues, style]);

  useEffect(() => {
    if (suppressNextStylePost.current) {
      suppressNextStylePost.current = false;
      return;
    }
    bridge.postStyleChanged({ component: "list", values: nextStyle });
  }, [nextStyle]);

  return null;
}
