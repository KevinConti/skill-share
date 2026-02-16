# Conditional Test

{{#if license}}
LICENSE_PRESENT: {{license}}
{{/if}}

{{#unless homepage}}
NO_HOMEPAGE_MARKER
{{/unless}}

{{#if homepage}}
HAS_HOMEPAGE
{{else}}
HOMEPAGE_ELSE_BRANCH
{{/if}}
