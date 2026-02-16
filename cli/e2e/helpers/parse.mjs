import yaml from "js-yaml";

/**
 * Parse a SKILL.md file into { frontmatter, body }.
 * SKILL.md format: ---\nyaml\n---\n\nbody
 */
export function parseSkillMd(content) {
  if (!content.startsWith("---\n")) {
    throw new Error("SKILL.md does not start with ---");
  }
  const secondFence = content.indexOf("\n---\n", 4);
  if (secondFence === -1) {
    throw new Error("SKILL.md missing closing --- fence");
  }
  const yamlStr = content.slice(4, secondFence);
  const frontmatter = yaml.load(yamlStr);
  const body = content.slice(secondFence + 5);
  return { frontmatter, body };
}
