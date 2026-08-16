import { createRoot } from "react-dom/client";
import { ComponentEditor } from "./ComponentEditor";
import { installSliderPointerGuard } from "./slider-pointer-guard";
import "./styles.css";

const rootElement = document.getElementById("root");
if (rootElement === null) {
  throw new Error("Component Editor root element is missing.");
}

installSliderPointerGuard(document);
createRoot(rootElement).render(<ComponentEditor />);
