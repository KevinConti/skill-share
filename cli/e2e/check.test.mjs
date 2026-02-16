import { describe, it } from "node:test";
import { strictEqual, ok } from "node:assert";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "./helpers/cli.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, "fixtures");

function fixture(name) {
  return resolve(FIXTURES, name);
}

describe("check", () => {
  it("valid skill exits 0 with name, version, and providers", () => {
    const result = run("check", fixture("all-providers"));
    strictEqual(result.exitCode, 0);
    ok(result.stdout.includes("all-providers-skill"), "should contain skill name");
    ok(result.stdout.includes("2.0.0"), "should contain version");
    ok(result.stdout.includes("openclaw"), "should list openclaw");
    ok(result.stdout.includes("claude-code"), "should list claude-code");
    ok(result.stdout.includes("codex"), "should list codex");
  });

  it("single-provider skill lists only that provider", () => {
    const result = run("check", fixture("basic"));
    strictEqual(result.exitCode, 0);
    ok(result.stdout.includes("openclaw"), "should list openclaw");
    ok(!result.stdout.includes("claude-code"), "should not list claude-code");
    ok(!result.stdout.includes("codex"), "should not list codex");
  });

  it("missing INSTRUCTIONS.md shows warning", () => {
    const result = run("check", fixture("error-missing-instructions"));
    // check command reads skill.yaml and checks for INSTRUCTIONS.md
    // It should still exit 0 but show a warning
    ok(
      result.stdout.includes("Warning") || result.stdout.includes("INSTRUCTIONS"),
      "should warn about missing INSTRUCTIONS.md"
    );
  });

  it("invalid skill exits 1", () => {
    const result = run("check", fixture("error-invalid-yaml"));
    strictEqual(result.exitCode, 1);
  });
});
