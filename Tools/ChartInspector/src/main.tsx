import { createRoot } from "react-dom/client";
import { ChartInspector } from "./ChartInspector";
import "./styles.css";

const rootElement = document.getElementById("root");
if (rootElement === null) {
  throw new Error("Chart Inspector root element is missing.");
}

createRoot(rootElement).render(<ChartInspector />);
