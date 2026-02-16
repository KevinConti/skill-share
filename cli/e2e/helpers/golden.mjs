import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { strictEqual } from "node:assert";

const __dirname = dirname(fileURLToPath(import.meta.url));
const GOLDEN_DIR = resolve(__dirname, "../golden");

const UPDATE_GOLDEN = process.env.UPDATE_GOLDEN === "1";

/**
 * Compare content against a golden file at golden/{relativePath}.
 * If UPDATE_GOLDEN=1, writes/overwrites the golden file instead.
 */
export function assertMatchesGolden(actual, relativePath) {
  const goldenPath = resolve(GOLDEN_DIR, relativePath);

  if (UPDATE_GOLDEN) {
    mkdirSync(dirname(goldenPath), { recursive: true });
    writeFileSync(goldenPath, actual, "utf-8");
    return;
  }

  if (!existsSync(goldenPath)) {
    throw new Error(
      `Golden file missing: ${relativePath}\n` +
      `Run with UPDATE_GOLDEN=1 to generate it.`
    );
  }

  const expected = readFileSync(goldenPath, "utf-8");
  strictEqual(
    actual,
    expected,
    `Golden file mismatch: ${relativePath}\n` +
    `Run with UPDATE_GOLDEN=1 to update.`
  );
}
