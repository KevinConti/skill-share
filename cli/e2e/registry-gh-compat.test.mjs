import { describe, it, before, after } from "node:test";
import { strictEqual, ok } from "node:assert";
import { execFileSync } from "node:child_process";
import { chmodSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { runWithEnv } from "./helpers/cli.mjs";
import { createTempDir, removeTempDir, fileExists } from "./helpers/fs.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, "fixtures");

function fixture(name) {
  return resolve(FIXTURES, name);
}

describe("registry gh compatibility", () => {
  let tmpdir;
  let env;
  let logPath;

  function clearLog() {
    writeFileSync(logPath, "");
  }

  function readLog() {
    return readFileSync(logPath, "utf-8");
  }

  before(() => {
    tmpdir = createTempDir();
    const binDir = `${tmpdir}/bin`;
    mkdirSync(binDir, { recursive: true });

    logPath = `${tmpdir}/gh.log`;
    writeFileSync(logPath, "");

    const tarballPath = `${tmpdir}/basic-skill-1.0.0.tar.gz`;
    execFileSync("tar", ["czf", tarballPath, "-C", FIXTURES, "basic"]);

    const ghPath = `${binDir}/gh`;
    writeFileSync(
      ghPath,
      `#!/usr/bin/env node
const fs = require("node:fs");
const args = process.argv.slice(2);
const logPath = process.env.FAKE_GH_LOG_PATH;
if (logPath) {
  fs.appendFileSync(logPath, args.join(" ") + "\\n");
}

function fail(msg) {
  if (msg) {
    console.error(msg);
  }
  process.exit(1);
}

function valueFor(flag) {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

if (args.length === 1 && args[0] === "--version") {
  console.log("gh version 2.86.0");
  process.exit(0);
}

if (args[0] === "release" && args[1] === "download") {
  if (args.includes("--latest")) {
    fail("unknown flag: --latest");
  }
  const dir = valueFor("--dir");
  const tarball = process.env.FAKE_GH_TARBALL_PATH;
  if (!dir || !tarball) {
    fail("missing required test env");
  }
  fs.mkdirSync(dir, { recursive: true });
  fs.copyFileSync(tarball, dir + "/basic-skill-1.0.0.tar.gz");
  process.exit(0);
}

if (args[0] === "release" && args[1] === "list") {
  if (args.includes("tagName,publishedAt,isLatest")) {
    console.log("v1.0.0\\t2025-01-01T00:00:00Z (latest)");
    process.exit(0);
  }
  if (args.includes("tagName")) {
    console.log("my-skill-v1.2.3");
    process.exit(0);
  }
  fail("unsupported release list args");
}

if (args[0] === "search" && args[1] === "repos") {
  console.log("owner/repo - test description");
  process.exit(0);
}

if (args[0] === "release" && args[1] === "create") {
  console.log("release created");
  process.exit(0);
}

fail("unexpected gh invocation: " + args.join(" "));
`,
    );
    chmodSync(ghPath, 0o755);

    env = {
      PATH: `${binDir}:${process.env.PATH}`,
      FAKE_GH_LOG_PATH: logPath,
      FAKE_GH_TARBALL_PATH: tarballPath,
    };
  });

  after(() => {
    removeTempDir(tmpdir);
  });

  it("install owner/repo does not pass --latest to gh release download", () => {
    clearLog();
    const outputDir = `${tmpdir}/installed-owner-repo`;
    const result = runWithEnv(
      env,
      "install",
      "owner/repo",
      "--output",
      outputDir,
    );

    strictEqual(result.exitCode, 0, `install failed: ${result.stderr}`);
    ok(result.stdout.includes("Installed basic-skill"), result.stdout);
    ok(fileExists(`${outputDir}/openclaw/basic-skill/SKILL.md`));

    const log = readLog();
    ok(log.includes("release download --repo owner/repo"), log);
    ok(!log.includes("--latest"), log);
  });

  it("install owner/repo/my-skill resolves a tag via gh release list", () => {
    clearLog();
    const outputDir = `${tmpdir}/installed-owner-repo-skill`;
    const result = runWithEnv(
      env,
      "install",
      "owner/repo/my-skill",
      "--output",
      outputDir,
    );

    strictEqual(result.exitCode, 0, `install failed: ${result.stderr}`);
    ok(fileExists(`${outputDir}/openclaw/basic-skill/SKILL.md`));

    const log = readLog();
    ok(log.includes("release list --repo owner/repo --json tagName"), log);
    ok(log.includes("release download my-skill-v1.2.3 --repo owner/repo"), log);
  });

  it("list owner/repo uses gh release list with supported flags", () => {
    clearLog();
    const result = runWithEnv(env, "list", "owner/repo");

    strictEqual(result.exitCode, 0, `list failed: ${result.stderr}`);
    ok(result.stdout.includes("v1.0.0"), result.stdout);

    const log = readLog();
    ok(
      log.includes(
        "release list --repo owner/repo --json tagName,publishedAt,isLatest",
      ),
      log,
    );
  });

  it("search uses gh search repos command", () => {
    clearLog();
    const result = runWithEnv(env, "search", "skill");

    strictEqual(result.exitCode, 0, `search failed: ${result.stderr}`);
    ok(result.stdout.includes("owner/repo - test description"), result.stdout);

    const log = readLog();
    ok(log.includes("search repos --topic skill-universe skill"), log);
  });

  it("publish uses gh release create command", () => {
    clearLog();
    const result = runWithEnv(
      env,
      "publish",
      fixture("basic"),
      "--repo",
      "owner/repo",
    );

    strictEqual(result.exitCode, 0, `publish failed: ${result.stderr}`);
    ok(result.stdout.includes("Published basic-skill"), result.stdout);

    const log = readLog();
    ok(log.includes("release create basic-skill-v1.0.0"), log);
  });
});
