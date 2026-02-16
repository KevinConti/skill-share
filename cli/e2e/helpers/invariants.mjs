import { strictEqual, ok } from "node:assert";
import { parseSkillMd } from "./parse.mjs";

/**
 * Scan for unresolved template syntax — catches LLMs leaving {{...}} in output.
 * Ignores backslash-escaped braces and {{{{raw}}}} markers.
 */
export function assertNoTemplateResidue(content) {
  // Match {{ not preceded by backslash, excluding {{{{raw}}}} markers
  const residue = content.match(/(?<!\\)\{\{(?!\{\{)[^}]*\}\}/g);
  strictEqual(residue, null, `Unresolved template syntax found: ${residue}`);
}

/** Verify frontmatter is valid parseable YAML with required fields. */
export function assertValidFrontmatter(content) {
  const { frontmatter } = parseSkillMd(content);
  ok(frontmatter.name, "frontmatter must have name");
  ok(frontmatter.description, "frontmatter must have description");
  ok(frontmatter.version, "frontmatter must have version");
}

/**
 * Verify provider-specific content doesn't leak into wrong provider output.
 * allProviderMarkers maps provider names to arrays of unique marker strings.
 */
export function assertNoProviderLeakage(content, provider, allProviderMarkers) {
  for (const [otherProvider, markers] of Object.entries(allProviderMarkers)) {
    if (otherProvider === provider) continue;
    for (const marker of markers) {
      ok(
        !content.includes(marker),
        `Provider leakage: "${marker}" (from ${otherProvider}) found in ${provider} output`
      );
    }
  }
}

/** Verify SKILL.md structure: starts with ---, has frontmatter, has body. */
export function assertValidSkillMdStructure(content) {
  ok(content.startsWith("---\n"), "SKILL.md must start with ---");
  const secondFence = content.indexOf("\n---\n", 4);
  ok(secondFence > 0, "SKILL.md must have closing --- fence");
  const body = content.slice(secondFence + 5);
  ok(body.trim().length > 0, "SKILL.md body must not be empty");
}
