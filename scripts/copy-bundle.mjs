// Copies the build artifacts into data/mcpviewer/ so Oxygen can serve them
// from disk:
//
//   dist/index.html      -> data/mcpviewer/index.html   (standalone page)
//   dist-lib/mcpviewer.js   -> data/mcpviewer/mcpviewer.js   (global mount)
//   dist-lib/mcpviewer.css  -> data/mcpviewer/mcpviewer.css  (global mount)
//
// Run via `npm run bundle` (build + copy).
import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const targetDir = resolve(here, "..", "data", "mcpviewer");

const files = [
  ["dist", "index.html"],
  ["dist-lib", "mcpviewer.js"],
  ["dist-lib", "mcpviewer.css"],
];

mkdirSync(targetDir, { recursive: true });

for (const [dir, name] of files) {
  const source = resolve(here, "..", dir, name);
  if (!existsSync(source)) {
    throw new Error(`missing build artifact: ${source} (run the build first)`);
  }
  const target = resolve(targetDir, name);
  copyFileSync(source, target);
  console.log(`copied ${source} -> ${target}`);
}
