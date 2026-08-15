import { createRoot } from "react-dom/client";
import { ChartInspector } from "./ChartInspector";
import { installSliderPointerGuard } from "./slider-pointer-guard";
import "./styles.css";

const rootElement = document.getElementById("root");
if (rootElement === null) {
  throw new Error("Chart Inspector root element is missing.");
}

installSliderPointerGuard(document);
createRoot(rootElement).render(<ChartInspector />);
