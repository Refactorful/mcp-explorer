// Copies the build artifacts into data/mcpexplorer/ so Oxygen can serve them
// from disk:
//
//   dist/index.html            -> data/mcpexplorer/index.html        (standalone page)
//   dist-lib/mcpexplorer.js    -> data/mcpexplorer/mcpexplorer.js    (global mount)
//   dist-lib/mcpexplorer.css   -> data/mcpexplorer/mcpexplorer.css   (global mount)
//
// Run via `npm run bundle` (build + copy).
import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const targetDir = resolve(here, "..", "data", "mcpexplorer");

const files = [
  ["dist", "index.html"],
  ["dist-lib", "mcpexplorer.js"],
  ["dist-lib", "mcpexplorer.css"],
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
