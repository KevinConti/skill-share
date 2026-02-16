import { describe, it } from "node:test";
import { strictEqual, ok } from "node:assert";
import { run } from "./helpers/cli.mjs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, "fixtures");

function fixture(name) {
  return resolve(FIXTURES, name);
}

describe("errors", () => {
  describe("invalid YAML", () => {
    it("exits 1 with parse error", () => {
      const result = run("compile", fixture("error-invalid-yaml"), "--target", "openclaw");
      strictEqual(result.exitCode, 1, "invalid YAML must exit 1");
      ok(
        result.stderr.toLowerCase().includes("parse error") ||
        result.stderr.toLowerCase().includes("error"),
        `stderr should mention error: ${result.stderr}`
      );
    });
  });

  describe("missing name", () => {
    it("exits 1 with name-related error", () => {
      const result = run("compile", fixture("error-missing-name"), "--target", "openclaw");
      strictEqual(result.exitCode, 1, "missing name must exit 1");
      ok(
        result.stderr.toLowerCase().includes("name"),
        `stderr should mention 'name': ${result.stderr}`
      );
    });
  });

  describe("bad version", () => {
    it("exits 1 with version-related error", () => {
      const result = run("compile", fixture("error-bad-version"), "--target", "openclaw");
      strictEqual(result.exitCode, 1, "bad version must exit 1");
      ok(
        result.stderr.toLowerCase().includes("version"),
        `stderr should mention 'version': ${result.stderr}`
      );
    });
  });

  describe("missing INSTRUCTIONS.md", () => {
    it("exits 1", () => {
      const result = run("compile", fixture("error-missing-instructions"), "--target", "openclaw");
      strictEqual(result.exitCode, 1, "missing INSTRUCTIONS.md must exit 1");
    });
  });

  describe("nonexistent directory", () => {
    it("exits 1", () => {
      const result = run("compile", "/tmp/nonexistent-skill-dir-99999", "--target", "openclaw");
      strictEqual(result.exitCode, 1, "nonexistent dir must exit 1");
    });
  });

  describe("unknown --target provider", () => {
    it("exits 1", () => {
      const result = run("compile", fixture("basic"), "--target", "unknown-provider");
      strictEqual(result.exitCode, 1, "unknown target must exit 1");
    });
  });

  describe("exit code contract", () => {
    const errorCases = [
      ["error-invalid-yaml", "openclaw"],
      ["error-missing-name", "openclaw"],
      ["error-bad-version", "openclaw"],
      ["error-missing-instructions", "openclaw"],
    ];

    for (const [fixtureName, target] of errorCases) {
      it(`${fixtureName} exits with code 1, never code 0`, () => {
        const result = run("compile", fixture(fixtureName), "--target", target);
        strictEqual(result.exitCode, 1, `${fixtureName} must exit 1, not 0`);
      });
    }
  });
});
