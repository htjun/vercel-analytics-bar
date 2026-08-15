import { describe, expect, it } from "vitest";
import { chartConfig, listConfig } from "./ChartInspector";

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

describe("Component Editor list sections", () => {
  it("opens only Actions and exposes the List controls", () => {
    const sectionNames = Object.keys(listConfig);

    expect(sectionNames).toEqual([
      "tabs",
      "rows",
      "layout",
      "label",
      "value",
      "emptyState",
      "introAnimation",
      "actions",
    ]);
    for (const sectionName of sectionNames) {
      expect(listConfig[sectionName as keyof typeof listConfig]._collapsed).toBe(
        sectionName !== "actions",
      );
    }
  });
});
