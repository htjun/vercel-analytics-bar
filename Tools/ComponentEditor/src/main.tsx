import { createRoot } from "react-dom/client";
import { ComponentEditor } from "./ComponentEditor";
import "./styles.css";

const rootElement = document.getElementById("root");
if (rootElement === null) {
  throw new Error("Component Editor root element is missing.");
}

createRoot(rootElement).render(<ComponentEditor />);
