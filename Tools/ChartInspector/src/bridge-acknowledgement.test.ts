import { describe, expect, it } from "vitest";
import { ChartInspectorBridge } from "./bridge";
import {
  CHART_STYLE_DEFAULT,
  INSPECTOR_PROTOCOL_VERSION,
  NATIVE_SOURCE,
} from "./generated/contract";

const state = (revision: number, values = CHART_STYLE_DEFAULT) => ({
  protocolVersion: INSPECTOR_PROTOCOL_VERSION,
  type: "state" as const,
  source: NATIVE_SOURCE,
  revision,
  values,
});

describe("ChartInspectorBridge acknowledgements", () => {
  it("does not republish an equivalent native acknowledgement", () => {
    const received: unknown[] = [];
    const bridge = new ChartInspectorBridge(() => undefined);
    bridge.subscribe((message) => received.push(message));
    bridge.receiveState(state(0));

    const changedStyle = { ...CHART_STYLE_DEFAULT, lineWidth: 3 };
    expect(bridge.postStyleChanged(changedStyle)).toBe(true);
    expect(bridge.receiveState(state(1, changedStyle))).toBe(true);

    expect(received).toEqual([state(0)]);
  });

  it("publishes a native correction for a pending revision", () => {
    const received: unknown[] = [];
    const bridge = new ChartInspectorBridge(() => undefined);
    bridge.subscribe((message) => received.push(message));
    bridge.receiveState(state(0));

    bridge.postStyleChanged({ ...CHART_STYLE_DEFAULT, lineWidth: 3 });
    const correctedState = state(1, { ...CHART_STYLE_DEFAULT, lineWidth: 2.5 });
    expect(bridge.receiveState(correctedState)).toBe(true);

    expect(received).toEqual([state(0), correctedState]);
  });

  it("keeps revisions monotonic while rapid changes are awaiting acknowledgement", () => {
    const sentRevisions: number[] = [];
    const bridge = new ChartInspectorBridge((message) => {
      if ("revision" in message) {
        sentRevisions.push(message.revision);
      }
    });
    bridge.receiveState(state(0));

    const firstStyle = { ...CHART_STYLE_DEFAULT, lineWidth: 2 };
    const secondStyle = { ...CHART_STYLE_DEFAULT, lineWidth: 3 };
    const thirdStyle = { ...CHART_STYLE_DEFAULT, lineWidth: 4 };
    bridge.postStyleChanged(firstStyle);
    bridge.postStyleChanged(secondStyle);
    bridge.receiveState(state(1, firstStyle));
    bridge.postStyleChanged(thirdStyle);

    expect(sentRevisions).toEqual([1, 2, 3]);
  });
});
