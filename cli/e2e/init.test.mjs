import { describe, it, before, after } from "node:test";
import { strictEqual, ok } from "node:assert";
import { run } from "./helpers/cli.mjs";
import { createTempDir, removeTempDir, fileExists, readFile } from "./helpers/fs.mjs";

describe("init", () => {
  let tmpdir;

  before(() => {
    tmpdir = createTempDir();
  });

  after(() => {
    removeTempDir(tmpdir);
  });

  it("creates scaffold with correct files", () => {
    const skillDir = `${tmpdir}/my-skill`;
    const result = run("init", skillDir);
    strictEqual(result.exitCode, 0);

    ok(fileExists(`${skillDir}/skill.yaml`), "skill.yaml should exist");
    ok(fileExists(`${skillDir}/INSTRUCTIONS.md`), "INSTRUCTIONS.md should exist");
    ok(fileExists(`${skillDir}/providers/openclaw/metadata.yaml`), "openclaw metadata should exist");
    ok(fileExists(`${skillDir}/providers/claude-code/metadata.yaml`), "claude-code metadata should exist");
    ok(fileExists(`${skillDir}/providers/codex/metadata.yaml`), "codex metadata should exist");
  });

  it("--name flag sets skill name", () => {
    const skillDir = `${tmpdir}/custom-name-skill`;
    const result = run("init", skillDir, "--name", "my-custom-name");
    strictEqual(result.exitCode, 0);

    const yaml = readFile(`${skillDir}/skill.yaml`);
    ok(yaml.includes("name: my-custom-name"), "skill.yaml should have custom name");
    ok(result.stdout.includes("my-custom-name"), "stdout should mention custom name");
  });

  it("name derived from path when --name not given", () => {
    const skillDir = `${tmpdir}/derived-name`;
    const result = run("init", skillDir);
    strictEqual(result.exitCode, 0);

    const yaml = readFile(`${skillDir}/skill.yaml`);
    ok(yaml.includes("name: derived-name"), "name should be derived from directory");
  });

  it("round-trip: init then compile succeeds", () => {
    const skillDir = `${tmpdir}/roundtrip-compile`;
    const initResult = run("init", skillDir);
    strictEqual(initResult.exitCode, 0);

    const outDir = `${tmpdir}/roundtrip-compile-out`;
    const compileResult = run("compile", skillDir, "--output", outDir);
    strictEqual(compileResult.exitCode, 0, `compile after init failed: ${compileResult.stderr}`);
  });

  it("round-trip: init then check succeeds", () => {
    const skillDir = `${tmpdir}/roundtrip-check`;
    const initResult = run("init", skillDir);
    strictEqual(initResult.exitCode, 0);

    const checkResult = run("check", skillDir);
    strictEqual(checkResult.exitCode, 0, `check after init failed: ${checkResult.stderr}`);
    ok(checkResult.stdout.includes("openclaw"), "check should list openclaw");
    ok(checkResult.stdout.includes("claude-code"), "check should list claude-code");
    ok(checkResult.stdout.includes("codex"), "check should list codex");
  });
});
