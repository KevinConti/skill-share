import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const CLI_PATH = resolve(__dirname, "../../bin/skill_universe.mjs");

/**
 * Run the skill_universe CLI with the given arguments.
 * Returns { stdout, stderr, exitCode } — never throws.
 */
export function run(...args) {
  try {
    const stdout = execFileSync("node", [CLI_PATH, ...args], {
      encoding: "utf-8",
      env: { ...process.env, NO_COLOR: "1" },
      timeout: 30_000,
    });
    return { stdout: stdout.trimEnd(), stderr: "", exitCode: 0 };
  } catch (err) {
    return {
      stdout: (err.stdout || "").trimEnd(),
      stderr: (err.stderr || "").trimEnd(),
      exitCode: err.status ?? 1,
    };
  }
}

export { CLI_PATH };
