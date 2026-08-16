import { DialRoot, useDialKitController } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useRef, useState } from "react";
import {
  chartStylesAreEquivalent,
  createBrowserBridge,
  listStylesAreEquivalent,
  numberStylesAreEquivalent,
} from "./bridge";
import type {
  BreakdownListStyle,
  ChartStyle,
  NumberStyle,
  NativeStateMessage,
} from "./generated/contract";
import {
  chartFieldConfig,
  chartDialValuesFromStyle,
  chartStyleFromDialValues,
  listDialValuesFromStyle,
  listFieldConfig,
  listStyleFromDialValues,
  numberDialValuesFromStyle,
  numberFieldConfig,
  numberStyleFromDialValues,
} from "./generated/component-editor-adapter";

const bridge = createBrowserBridge();
const maximumNumberPreviewValue = BigInt("9223372036854775807");
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

export const numbersConfig = {
  preview: {
    _collapsed: false,
    testValue: { type: "text" as const, default: "325,922", placeholder: "0" },
  },
  typography: {
    ...numberFieldConfig.typography,
    color: { type: "color" as const, default: "#262626" as const },
    fontSize: [48, 24, 72, 1] as [number, number, number, number],
    fontWeight: [280, 100, 900, 1] as [number, number, number, number],
    opticalSize: [32, 14, 32, 1] as [number, number, number, number],
    tracking: [-0.25, -2, 2, 0.05] as [number, number, number, number],
    _collapsed: true,
  },
  features: {
    ...numberFieldConfig.features,
    commaStyle: {
      ...numberFieldConfig.features.commaStyle,
      default: "square" as const,
    },
    slashedZero: true,
    openFour: true,
    openSix: true,
    flatTopThree: true,
    _collapsed: true,
  },
  animation: {
    ...numberFieldConfig.animation,
    duration: [0.4, 0.1, 2, 0.05] as [number, number, number, number],
    easing: {
      ...numberFieldConfig.animation.easing,
      default: "snappy" as const,
    },
    _collapsed: true,
  },
  actions: {
    _collapsed: false,
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
      {nativeState?.component === "numbers" && (
        <NumbersControls style={nativeState.values} testValue={nativeState.testValue} />
      )}
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

function NumbersControls({ style, testValue: nativeTestValue }: { style: NumberStyle; testValue: string }) {
  const suppressNextStylePost = useRef(false);
  const latestValidTestValue = useRef("325,922");
  const dial = useDialKitController("Numbers", numbersConfig, {
    id: "vercel-analytics-numbers",
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
  const nextStyle = useMemo(() => numberStyleFromDialValues(values), [values]);
  const testValue = values.preview.testValue;

  useEffect(() => {
    const currentDialStyle = numberStyleFromDialValues(getDialValues());
    suppressNextStylePost.current = !numberStylesAreEquivalent(currentDialStyle, style);
    const formattedTestValue = formatNumberPreviewValue(nativeTestValue);
    latestValidTestValue.current = formattedTestValue;
    setDialValues({
      ...numberDialValuesFromStyle(style),
      preview: { testValue: formattedTestValue },
    });
  }, [getDialValues, nativeTestValue, setDialValues, style]);

  useEffect(() => {
    if (suppressNextStylePost.current) {
      suppressNextStylePost.current = false;
      return;
    }
    bridge.postStyleChanged({ component: "numbers", values: nextStyle });
  }, [nextStyle]);

  useEffect(() => {
    const canonicalTestValue = canonicalNumberPreviewValue(testValue);
    if (canonicalTestValue === undefined) {
      setDialValues({ preview: { testValue: latestValidTestValue.current } });
      return;
    }

    const formattedTestValue = formatNumberPreviewValue(canonicalTestValue);
    latestValidTestValue.current = formattedTestValue;
    bridge.postNumberPreviewValue(canonicalTestValue);
    if (testValue !== formattedTestValue) {
      setDialValues({ preview: { testValue: formattedTestValue } });
    }
  }, [setDialValues, testValue]);

  return null;
}

function canonicalNumberPreviewValue(value: string): string | undefined {
  const digits = value.replaceAll(",", "").trim();
  if (!/^\d+$/.test(digits)) {
    return undefined;
  }

  const parsedValue = BigInt(digits);
  return parsedValue <= maximumNumberPreviewValue ? parsedValue.toString() : undefined;
}

function formatNumberPreviewValue(value: string): string {
  return new Intl.NumberFormat("en-US").format(BigInt(value));
}
