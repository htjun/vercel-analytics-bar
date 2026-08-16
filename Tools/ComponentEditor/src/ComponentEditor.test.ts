import { describe, expect, it } from "vitest";
import { chartConfig, listConfig, numbersConfig } from "./ComponentEditor";

describe("Component Editor sections", () => {
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

describe("Component Editor numbers sections", () => {
  it("opens Preview and Actions and exposes the Numbers controls", () => {
    const sectionNames = Object.keys(numbersConfig);

    expect(sectionNames).toEqual(["preview", "typography", "features", "animation", "actions"]);
    expect(numbersConfig.preview.testValue).toEqual({
      type: "text",
      default: "325,922",
      placeholder: "0",
    });
    expect(numbersConfig).toMatchObject({
      typography: {
        color: { type: "color", default: "#262626" },
        fontSize: [48, 24, 72, 1],
        fontWeight: [280, 100, 900, 1],
        opticalSize: [32, 14, 32, 1],
        tracking: [-0.25, -2, 2, 0.05],
      },
      features: {
        commaStyle: { default: "square" },
        slashedZero: true,
        openFour: true,
        openSix: true,
        flatTopThree: true,
      },
      animation: {
        duration: [0.4, 0.1, 2, 0.05],
        easing: { default: "snappy" },
      },
      actions: {
        reset: { type: "action", label: "Reset to defaults" },
        copyStyle: { type: "action", label: "Copy canonical JSON" },
      },
    });
    for (const sectionName of sectionNames) {
      expect(numbersConfig[sectionName as keyof typeof numbersConfig]._collapsed).toBe(
        sectionName !== "preview" && sectionName !== "actions",
      );
    }
  });
});
