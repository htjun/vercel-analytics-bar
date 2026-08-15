import { describe, expect, it } from "vitest";
import { chartConfig } from "./ChartInspector";

describe("Chart Inspector sections", () => {
  it("opens only Actions and places it after Intro Animation", () => {
    const sectionNames = Object.keys(chartConfig);

    expect(sectionNames).toEqual([
      "line",
      "area",
      "layout",
      "axes",
      "verticalGridLines",
      "horizontalGridLines",
      "verticalAxisTicks",
      "horizontalAxisTicks",
      "chartContainer",
      "borderDash",
      "introAnimation",
      "actions",
    ]);

    for (const sectionName of sectionNames) {
      expect(chartConfig[sectionName as keyof typeof chartConfig]._collapsed).toBe(
        sectionName !== "actions",
      );
    }
  });
});
