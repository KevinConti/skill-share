import { describe, it, before, after } from "node:test";
import { strictEqual, ok } from "node:assert";
import { execSync } from "node:child_process";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { run, runWithEnv } from "./helpers/cli.mjs";
import { createTempDir, removeTempDir, readFile, fileExists, listDir } from "./helpers/fs.mjs";
import { parseSkillMd } from "./helpers/parse.mjs";
import { assertMatchesGolden } from "./helpers/golden.mjs";
import {
  assertNoTemplateResidue,
  assertValidFrontmatter,
  assertValidSkillMdStructure,
} from "./helpers/invariants.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, "fixtures");

function fixture(name) {
  return resolve(FIXTURES, name);
}

describe("compile", () => {
  let tmpdir;

  before(() => {
    tmpdir = createTempDir();
  });

  after(() => {
    removeTempDir(tmpdir);
  });

  describe("basic fixture", () => {
    it("compiles successfully with exit 0", () => {
      const result = run("compile", fixture("basic"), "--target", "openclaw", "--output", tmpdir);
      strictEqual(result.exitCode, 0);
      ok(result.stdout.includes("Compiled openclaw"), `stdout: ${result.stdout}`);
    });

    it("produces SKILL.md with correct structure", () => {
      const content = readFile(`${tmpdir}/openclaw/basic-skill/SKILL.md`);
      assertValidSkillMdStructure(content);

      const { frontmatter, body } = parseSkillMd(content);
      strictEqual(frontmatter.name, "basic-skill");
      strictEqual(frontmatter.version, "1.0.0");
      ok(frontmatter.description);
      ok(body.includes("basic skill with no template directives"));
    });

    it("has no template residue", () => {
      const content = readFile(`${tmpdir}/openclaw/basic-skill/SKILL.md`);
      assertNoTemplateResidue(content);
    });

    it("matches golden file", () => {
      const content = readFile(`${tmpdir}/openclaw/basic-skill/SKILL.md`);
      assertMatchesGolden(content, "basic/openclaw.md");
    });
  });

  describe("all-providers fixture", () => {
    let allTmpdir;

    before(() => {
      allTmpdir = createTempDir();
      const result = run("compile", fixture("all-providers"), "--output", allTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(allTmpdir);
    });

    it("creates correct directory structure for openclaw", () => {
      ok(fileExists(`${allTmpdir}/openclaw/all-providers-skill/SKILL.md`));
    });

    it("creates correct directory structure for claude-code", () => {
      ok(fileExists(`${allTmpdir}/claude-code/all-providers-skill/SKILL.md`));
    });

    it("creates correct directory structure for codex", () => {
      ok(fileExists(`${allTmpdir}/codex/.agents/skills/all-providers-skill/SKILL.md`));
      ok(fileExists(`${allTmpdir}/codex/.agents/skills/all-providers-skill/agents/openai.yaml`));
    });

    it("openclaw output matches golden file", () => {
      const content = readFile(`${allTmpdir}/openclaw/all-providers-skill/SKILL.md`);
      assertValidFrontmatter(content);
      assertNoTemplateResidue(content);
      assertMatchesGolden(content, "all-providers/openclaw.md");
    });

    it("claude-code output matches golden file", () => {
      const content = readFile(`${allTmpdir}/claude-code/all-providers-skill/SKILL.md`);
      assertValidFrontmatter(content);
      assertNoTemplateResidue(content);
      assertMatchesGolden(content, "all-providers/claude-code.md");
    });

    it("codex SKILL.md matches golden file", () => {
      const content = readFile(`${allTmpdir}/codex/.agents/skills/all-providers-skill/SKILL.md`);
      assertValidFrontmatter(content);
      assertNoTemplateResidue(content);
      assertMatchesGolden(content, "all-providers/codex.md");
    });

    it("codex openai.yaml matches golden file", () => {
      const content = readFile(`${allTmpdir}/codex/.agents/skills/all-providers-skill/agents/openai.yaml`);
      assertMatchesGolden(content, "all-providers/codex.openai.yaml");
    });
  });

  describe("template variable interpolation", () => {
    let tvTmpdir;

    before(() => {
      tvTmpdir = createTempDir();
      const result = run("compile", fixture("template-variables"), "--target", "openclaw", "--output", tvTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(tvTmpdir);
    });

    it("resolves variables in body", () => {
      const content = readFile(`${tvTmpdir}/openclaw/template-variables/SKILL.md`);
      const { body } = parseSkillMd(content);

      ok(body.includes("template-variables v1.0.0"), "name and version resolved");
      ok(body.includes("Tests template variable interpolation"), "description resolved");
      ok(body.includes("Licensed under MIT"), "license resolved");
      ok(body.includes("🧪"), "meta.emoji resolved");
    });

    it("has no template residue", () => {
      const content = readFile(`${tvTmpdir}/openclaw/template-variables/SKILL.md`);
      assertNoTemplateResidue(content);
      assertValidFrontmatter(content);
    });

    it("matches golden file", () => {
      const content = readFile(`${tvTmpdir}/openclaw/template-variables/SKILL.md`);
      assertMatchesGolden(content, "template-variables/openclaw.md");
    });
  });

  describe("template provider blocks", () => {
    let tpbTmpdir;

    before(() => {
      tpbTmpdir = createTempDir();
      const result = run("compile", fixture("template-provider-blocks"), "--output", tpbTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(tpbTmpdir);
    });

    it("openclaw includes openclaw content, excludes claude-code content", () => {
      const content = readFile(`${tpbTmpdir}/openclaw/provider-blocks/SKILL.md`);
      ok(content.includes("OPENCLAW_ONLY_CONTENT"), "should include openclaw content");
      ok(!content.includes("CLAUDE_CODE_ONLY_CONTENT"), "should exclude claude-code content");
      ok(!content.includes("CODEX_ONLY_CONTENT"), "should exclude codex-only content");
      ok(content.includes("SHARED_OPENCLAW_CODEX"), "should include shared openclaw+codex");
      ok(content.includes("Common content for all providers"), "should include common content");
    });

    it("claude-code includes only claude-code content", () => {
      const content = readFile(`${tpbTmpdir}/claude-code/provider-blocks/SKILL.md`);
      ok(content.includes("CLAUDE_CODE_ONLY_CONTENT"), "should include claude-code content");
      ok(!content.includes("OPENCLAW_ONLY_CONTENT"), "should exclude openclaw content");
      ok(!content.includes("CODEX_ONLY_CONTENT"), "should exclude codex-only content");
      ok(!content.includes("SHARED_OPENCLAW_CODEX"), "should exclude shared openclaw+codex");
    });

    it("codex includes codex and shared openclaw+codex content", () => {
      const content = readFile(`${tpbTmpdir}/codex/.agents/skills/provider-blocks/SKILL.md`);
      ok(content.includes("CODEX_ONLY_CONTENT"), "should include codex content");
      ok(content.includes("SHARED_OPENCLAW_CODEX"), "should include shared openclaw+codex");
      ok(!content.includes("OPENCLAW_ONLY_CONTENT"), "should exclude openclaw content");
      ok(!content.includes("CLAUDE_CODE_ONLY_CONTENT"), "should exclude claude-code content");
    });

    it("openclaw matches golden file", () => {
      const content = readFile(`${tpbTmpdir}/openclaw/provider-blocks/SKILL.md`);
      assertMatchesGolden(content, "template-provider-blocks/openclaw.md");
    });

    it("claude-code matches golden file", () => {
      const content = readFile(`${tpbTmpdir}/claude-code/provider-blocks/SKILL.md`);
      assertMatchesGolden(content, "template-provider-blocks/claude-code.md");
    });

    it("codex matches golden file", () => {
      const content = readFile(`${tpbTmpdir}/codex/.agents/skills/provider-blocks/SKILL.md`);
      assertMatchesGolden(content, "template-provider-blocks/codex.md");
    });
  });

  describe("template conditionals", () => {
    let tcTmpdir;

    before(() => {
      tcTmpdir = createTempDir();
      const result = run("compile", fixture("template-conditionals"), "--target", "openclaw", "--output", tcTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(tcTmpdir);
    });

    it("renders if/unless/else correctly", () => {
      const content = readFile(`${tcTmpdir}/openclaw/conditionals-test/SKILL.md`);
      const { body } = parseSkillMd(content);

      // license is set → #if license should render
      ok(body.includes("LICENSE_PRESENT: MIT"), "if license should render");

      // homepage is not set → #unless homepage should render
      ok(body.includes("NO_HOMEPAGE_MARKER"), "unless homepage should render");

      // homepage is not set → else branch should render
      ok(!body.includes("HAS_HOMEPAGE"), "if homepage should not render");
      ok(body.includes("HOMEPAGE_ELSE_BRANCH"), "else branch should render");
    });

    it("matches golden file", () => {
      const content = readFile(`${tcTmpdir}/openclaw/conditionals-test/SKILL.md`);
      assertNoTemplateResidue(content);
      assertMatchesGolden(content, "template-conditionals/openclaw.md");
    });
  });

  describe("template loops", () => {
    let tlTmpdir;

    before(() => {
      tlTmpdir = createTempDir();
      const result = run("compile", fixture("template-loops"), "--target", "openclaw", "--output", tlTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(tlTmpdir);
    });

    it("renders each config field as a list item", () => {
      const content = readFile(`${tlTmpdir}/openclaw/loops-test/SKILL.md`);
      const { body } = parseSkillMd(content);

      ok(body.includes("**api_key**: API key for auth"), "first config item");
      ok(body.includes("**timeout**: Timeout in seconds"), "second config item");
      ok(body.includes("**debug**: Enable debug mode"), "third config item");
    });

    it("matches golden file", () => {
      const content = readFile(`${tlTmpdir}/openclaw/loops-test/SKILL.md`);
      assertNoTemplateResidue(content);
      assertMatchesGolden(content, "template-loops/openclaw.md");
    });
  });

  describe("template escaping", () => {
    let teTmpdir;

    before(() => {
      teTmpdir = createTempDir();
      const result = run("compile", fixture("template-escaping"), "--target", "openclaw", "--output", teTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(teTmpdir);
    });

    it("preserves backslash-escaped and raw block content", () => {
      const content = readFile(`${teTmpdir}/openclaw/escaping-test/SKILL.md`);
      const { body } = parseSkillMd(content);

      ok(body.includes("{{literal_braces}}"), "backslash-escaped braces preserved");
      ok(body.includes("{{not_a_variable}}"), "raw block content preserved");
      ok(body.includes("{{another_raw_thing}}"), "raw block content preserved");
      ok(body.includes("Normal variable: escaping-test"), "normal variable resolved");
    });

    it("matches golden file", () => {
      const content = readFile(`${teTmpdir}/openclaw/escaping-test/SKILL.md`);
      assertMatchesGolden(content, "template-escaping/openclaw.md");
    });
  });

  describe("script merging", () => {
    let smTmpdir;

    before(() => {
      smTmpdir = createTempDir();
      const result = run("compile", fixture("script-merging"), "--target", "openclaw", "--output", smTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(smTmpdir);
    });

    it("provider script overrides shared script", () => {
      const script = readFile(`${smTmpdir}/openclaw/script-merging/scripts/common.sh`);
      ok(script.includes("OPENCLAW_OVERRIDE_SCRIPT"), "provider script should override shared");
      ok(!script.includes("SHARED_COMMON_SCRIPT"), "shared script content should not be present");
    });

    it("SKILL.md matches golden file", () => {
      const content = readFile(`${smTmpdir}/openclaw/script-merging/SKILL.md`);
      assertMatchesGolden(content, "script-merging/openclaw.md");
    });
  });

  describe("provider instructions", () => {
    let piTmpdir;

    before(() => {
      piTmpdir = createTempDir();
      const result = run("compile", fixture("provider-instructions"), "--target", "openclaw", "--output", piTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(piTmpdir);
    });

    it("appends provider-specific instructions", () => {
      const content = readFile(`${piTmpdir}/openclaw/provider-instructions/SKILL.md`);
      const { body } = parseSkillMd(content);

      ok(body.includes("Main instructions content"), "main instructions present");
      ok(body.includes("PROVIDER_APPENDED_CONTENT"), "provider instructions appended");
    });

    it("matches golden file", () => {
      const content = readFile(`${piTmpdir}/openclaw/provider-instructions/SKILL.md`);
      assertMatchesGolden(content, "provider-instructions/openclaw.md");
    });
  });

  describe("metadata merging", () => {
    let mmTmpdir;

    before(() => {
      mmTmpdir = createTempDir();
      const result = run("compile", fixture("metadata-merging"), "--target", "openclaw", "--output", mmTmpdir);
      strictEqual(result.exitCode, 0);
    });

    after(() => {
      removeTempDir(mmTmpdir);
    });

    it("provider metadata overrides universal description", () => {
      const content = readFile(`${mmTmpdir}/openclaw/metadata-merging/SKILL.md`);
      const { frontmatter } = parseSkillMd(content);

      strictEqual(frontmatter.description, "Provider-overridden description");
    });

    it("matches golden file", () => {
      const content = readFile(`${mmTmpdir}/openclaw/metadata-merging/SKILL.md`);
      assertMatchesGolden(content, "metadata-merging/openclaw.md");
    });
  });

  describe("CLI flags", () => {
    it("--target produces only the targeted provider", () => {
      const tmp = createTempDir();
      try {
        run("compile", fixture("all-providers"), "--target", "openclaw", "--output", tmp);
        const dirs = listDir(tmp);
        ok(dirs.includes("openclaw"), "openclaw dir should exist");
        ok(!dirs.includes("claude-code"), "claude-code dir should not exist");
        ok(!dirs.includes("codex"), "codex dir should not exist");
      } finally {
        removeTempDir(tmp);
      }
    });

    it("--providers produces only the specified providers", () => {
      const tmp = createTempDir();
      try {
        run("compile", fixture("all-providers"), "--providers", "openclaw,codex", "--output", tmp);
        const dirs = listDir(tmp);
        ok(dirs.includes("openclaw"), "openclaw dir should exist");
        ok(dirs.includes("codex"), "codex dir should exist");
        ok(!dirs.includes("claude-code"), "claude-code dir should not exist");
      } finally {
        removeTempDir(tmp);
      }
    });

    it("default output goes to ~/.skill-universe (or USERPROFILE/.skill-universe)", () => {
      const tmp = createTempDir();
      const skillDir = `${tmp}/my-skill`;
      const homeDir = `${tmp}/home`;
      // Copy basic fixture to tmp
      execSync(`cp -r ${fixture("basic")} ${skillDir}`);
      execSync(`mkdir -p ${homeDir}`);
      try {
        const result = runWithEnv(
          { HOME: homeDir, USERPROFILE: homeDir },
          "compile",
          skillDir,
          "--target",
          "openclaw"
        );
        strictEqual(result.exitCode, 0);
        ok(fileExists(`${homeDir}/.skill-universe/openclaw/basic-skill/SKILL.md`));
      } finally {
        removeTempDir(tmp);
      }
    });

    it("stdout contains 'Compiled <provider> -> <dir>' per provider", () => {
      const tmp = createTempDir();
      try {
        const result = run("compile", fixture("all-providers"), "--output", tmp);
        strictEqual(result.exitCode, 0);
        ok(result.stdout.includes("Compiled openclaw ->"), "should mention openclaw");
        ok(result.stdout.includes("Compiled claude-code ->"), "should mention claude-code");
        ok(result.stdout.includes("Compiled codex ->"), "should mention codex");
      } finally {
        removeTempDir(tmp);
      }
    });
  });
});
