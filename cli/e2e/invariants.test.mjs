import { describe, it, before, after } from "node:test";
import { strictEqual, ok, deepStrictEqual } from "node:assert";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { run } from "./helpers/cli.mjs";
import { createTempDir, removeTempDir, readFile, fileExists, listFilesRecursive } from "./helpers/fs.mjs";
import { parseSkillMd } from "./helpers/parse.mjs";
import {
  assertNoTemplateResidue,
  assertValidFrontmatter,
  assertValidSkillMdStructure,
  assertNoProviderLeakage,
} from "./helpers/invariants.mjs";

const __dirname = dirname(fileURLToPath(import.meta.url));
const FIXTURES = resolve(__dirname, "fixtures");

function fixture(name) {
  return resolve(FIXTURES, name);
}

describe("compiler invariants", () => {
  let tmpdir;

  before(() => {
    tmpdir = createTempDir();
    const result = run("compile", fixture("all-providers"), "--output", tmpdir);
    strictEqual(result.exitCode, 0, `compile failed: ${result.stderr}`);
  });

  after(() => {
    removeTempDir(tmpdir);
  });

  function skillMdPath(provider) {
    if (provider === "codex") {
      return `${tmpdir}/codex/.agents/skills/all-providers-skill/SKILL.md`;
    }
    return `${tmpdir}/${provider}/all-providers-skill/SKILL.md`;
  }

  const providers = ["openclaw", "claude-code", "codex"];

  for (const provider of providers) {
    describe(`${provider} output invariants`, () => {
      it("produces valid SKILL.md structure", () => {
        const content = readFile(skillMdPath(provider));
        assertValidSkillMdStructure(content);
      });

      it("has no unresolved template syntax", () => {
        const content = readFile(skillMdPath(provider));
        assertNoTemplateResidue(content);
      });

      it("has valid YAML frontmatter", () => {
        const content = readFile(skillMdPath(provider));
        assertValidFrontmatter(content);
      });

      it("contains no provider-specific content from other providers", () => {
        const content = readFile(skillMdPath(provider));
        assertNoProviderLeakage(content, provider, {
          openclaw: ["OpenClaw Section", "This content is only for OpenClaw"],
          "claude-code": ["Claude Code Section", "This content is only for Claude Code"],
          codex: ["Codex Section", "This content is only for Codex"],
        });
      });
    });
  }

  describe("cross-provider consistency", () => {
    it("all providers have same name in frontmatter", () => {
      const names = providers.map((p) => parseSkillMd(readFile(skillMdPath(p))).frontmatter.name);
      strictEqual(names[0], names[1], "openclaw and claude-code name must match");
      strictEqual(names[1], names[2], "claude-code and codex name must match");
    });

    it("all providers have same version in frontmatter", () => {
      const versions = providers.map((p) => {
        const v = parseSkillMd(readFile(skillMdPath(p))).frontmatter.version;
        return String(v);
      });
      strictEqual(versions[0], versions[1], "openclaw and claude-code version must match");
      strictEqual(versions[1], versions[2], "claude-code and codex version must match");
    });

    it("all providers have same description in frontmatter", () => {
      const descs = providers.map((p) => parseSkillMd(readFile(skillMdPath(p))).frontmatter.description);
      strictEqual(descs[0], descs[1], "openclaw and claude-code description must match");
      strictEqual(descs[1], descs[2], "claude-code and codex description must match");
    });
  });

  describe("provider format contracts", () => {
    it("openclaw has metadata.openclaw section", () => {
      const content = readFile(skillMdPath("openclaw"));
      ok(content.includes("metadata.openclaw:"), "openclaw should have metadata.openclaw section");
    });

    it("claude-code has flat frontmatter (no metadata.openclaw nesting)", () => {
      const content = readFile(skillMdPath("claude-code"));
      ok(!content.includes("metadata.openclaw:"), "claude-code should not have metadata.openclaw");
      ok(!content.includes("metadata.claude-code:"), "claude-code should not have nested metadata");
    });

    it("codex has minimal frontmatter (name, desc, version only)", () => {
      const { frontmatter } = parseSkillMd(readFile(skillMdPath("codex")));
      const keys = Object.keys(frontmatter);
      deepStrictEqual(keys.sort(), ["description", "name", "version"].sort(),
        "codex frontmatter should only have name, description, version");
    });

    it("codex generates agents/openai.yaml", () => {
      ok(
        fileExists(`${tmpdir}/codex/.agents/skills/all-providers-skill/agents/openai.yaml`),
        "codex should have agents/openai.yaml"
      );
    });

    it("non-codex providers do NOT have agents/ directory", () => {
      ok(
        !fileExists(`${tmpdir}/openclaw/all-providers-skill/agents`),
        "openclaw should not have agents dir"
      );
      ok(
        !fileExists(`${tmpdir}/claude-code/all-providers-skill/agents`),
        "claude-code should not have agents dir"
      );
    });
  });

  describe("idempotency", () => {
    it("compiling the same skill twice produces identical output", () => {
      const tmpdir1 = createTempDir();
      const tmpdir2 = createTempDir();
      try {
        const r1 = run("compile", fixture("all-providers"), "--output", tmpdir1);
        const r2 = run("compile", fixture("all-providers"), "--output", tmpdir2);
        strictEqual(r1.exitCode, 0);
        strictEqual(r2.exitCode, 0);

        const files1 = listFilesRecursive(tmpdir1);
        const files2 = listFilesRecursive(tmpdir2);
        deepStrictEqual(files1, files2, "file lists should be identical");

        for (const file of files1) {
          const content1 = readFile(`${tmpdir1}/${file}`);
          const content2 = readFile(`${tmpdir2}/${file}`);
          strictEqual(content1, content2, `file ${file} should be identical across runs`);
        }
      } finally {
        removeTempDir(tmpdir1);
        removeTempDir(tmpdir2);
      }
    });
  });

  describe("output completeness", () => {
    it("output contains no unexpected files for openclaw", () => {
      const files = listFilesRecursive(`${tmpdir}/openclaw/all-providers-skill`);
      deepStrictEqual(files, ["SKILL.md"], "openclaw should only have SKILL.md");
    });

    it("output contains no unexpected files for claude-code", () => {
      const files = listFilesRecursive(`${tmpdir}/claude-code/all-providers-skill`);
      deepStrictEqual(files, ["SKILL.md"], "claude-code should only have SKILL.md");
    });

    it("output contains only expected files for codex", () => {
      const files = listFilesRecursive(`${tmpdir}/codex/.agents/skills/all-providers-skill`);
      deepStrictEqual(files, ["SKILL.md", "agents/openai.yaml"].sort(),
        "codex should only have SKILL.md and agents/openai.yaml");
    });
  });
});
