// Copies the build artifacts into bundle/mcpexplorer/ so Oxygen can serve them
// from disk:
//
//   dist/index.html            -> bundle/mcpexplorer/index.html        (standalone page)
//   dist-lib/mcpexplorer.js    -> bundle/mcpexplorer/mcpexplorer.js    (global mount)
//   dist-lib/mcpexplorer.css   -> bundle/mcpexplorer/mcpexplorer.css   (global mount)
//   assets/icon-compass.svg    -> bundle/mcpexplorer/icon.svg          (favicon for hosts)
//
// Run via `npm run bundle` (build + copy).
import { mkdirSync, copyFileSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const targetDir = resolve(here, "..", "bundle", "mcpexplorer");

const files = [
  [resolve(here, "..", "dist", "index.html"), "index.html"],
  [resolve(here, "..", "dist-lib", "mcpexplorer.js"), "mcpexplorer.js"],
  [resolve(here, "..", "dist-lib", "mcpexplorer.css"), "mcpexplorer.css"],
  [resolve(here, "..", "assets", "icon-compass.svg"), "icon.svg"],
];

mkdirSync(targetDir, { recursive: true });

for (const [source, name] of files) {
  if (!existsSync(source)) {
    throw new Error(`missing build artifact: ${source} (run the build first)`);
  }
  const target = resolve(targetDir, name);
  copyFileSync(source, target);
  console.log(`copied ${source} -> ${target}`);
}
