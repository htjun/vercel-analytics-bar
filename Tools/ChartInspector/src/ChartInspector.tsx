import { DialRoot, useDialKitController } from "dialkit";
import "dialkit/styles.css";
import { useEffect, useMemo, useState } from "react";
import { ChartStyle, createBrowserBridge } from "./bridge";

const bridge = createBrowserBridge();

export function ChartInspector() {
  const [nativeStyle, setNativeStyle] = useState<ChartStyle>();
  const dial = useDialKitController(
    "Visitors Chart",
    {
      lineWidth: [2, 0.5, 12, 0.5],
    },
    {
      id: "vercel-analytics-visitors-chart",
    },
  );
  const setDialValue = dial.setValue;
  const lineWidth = dial.values.lineWidth;
  const nextStyle = useMemo(
    () => (nativeStyle === undefined ? undefined : { ...nativeStyle, lineWidth }),
    [lineWidth, nativeStyle],
  );

  useEffect(() => {
    window.__chartInspectorReceiveState = (message) => bridge.receiveState(message);
    const unsubscribe = bridge.subscribe((message) => {
      setNativeStyle(message.values);
      setDialValue("lineWidth", message.values.lineWidth);
    });
    bridge.postReady();

    return () => {
      unsubscribe();
      delete window.__chartInspectorReceiveState;
    };
  }, [setDialValue]);

  useEffect(() => {
    if (nextStyle !== undefined) {
      bridge.postStyleChanged(nextStyle);
    }
  }, [nextStyle]);

  return <DialRoot mode="inline" theme="system" productionEnabled />;
}
