import { describe, it } from "node:test";
import { strictEqual, ok } from "node:assert";
import { run } from "./helpers/cli.mjs";

describe("cli-basics", () => {
  describe("version", () => {
    it("exits 0 and prints version string", () => {
      const result = run("version");
      strictEqual(result.exitCode, 0);
      ok(
        /^skill-universe \d+\.\d+\.\d+$/.test(result.stdout),
        `Expected 'skill-universe X.Y.Z', got: ${result.stdout}`
      );
    });
  });

  describe("help", () => {
    it("exits 0 with 'help' command", () => {
      const result = run("help");
      strictEqual(result.exitCode, 0);
      ok(result.stdout.includes("Usage:"), "help should contain 'Usage:'");
    });

    it("exits 0 with '--help' flag", () => {
      const result = run("--help");
      strictEqual(result.exitCode, 0);
      ok(result.stdout.includes("Usage:"), "--help should contain 'Usage:'");
    });

    it("help text contains all known commands", () => {
      const result = run("help");
      const commands = [
        "compile",
        "check",
        "init",
        "import",
        "config",
        "publish",
        "search",
        "install",
        "list",
        "version",
        "help",
      ];
      for (const cmd of commands) {
        ok(
          result.stdout.includes(cmd),
          `Help text missing command: ${cmd}`
        );
      }
    });

    it("help text lists all providers", () => {
      const result = run("help");
      ok(result.stdout.includes("openclaw"), "help should list openclaw");
      ok(result.stdout.includes("claude-code"), "help should list claude-code");
      ok(result.stdout.includes("codex"), "help should list codex");
    });
  });

  describe("error cases", () => {
    it("no arguments exits 1", () => {
      const result = run();
      strictEqual(result.exitCode, 1);
    });

    it("unknown command exits 1", () => {
      const result = run("nonsense");
      strictEqual(result.exitCode, 1);
    });
  });
});
