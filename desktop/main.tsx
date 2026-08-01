import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { MarkdownViewer } from "../app/MarkdownViewer";
import "../app/globals.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("Não foi possível iniciar a interface do Lume.");
}

createRoot(root).render(
  <StrictMode>
    <MarkdownViewer />
  </StrictMode>,
);
