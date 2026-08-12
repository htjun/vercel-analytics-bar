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
const chartConfig = {
  ...chartFieldConfig,
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
