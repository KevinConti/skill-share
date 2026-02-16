---
name: escaping-test
description: "Tests template escaping mechanisms"
version: 1.0.0
metadata.openclaw:
  emoji: 🔒
  requires:
    bins: []
  install: []
---

# Escaping Test

Backslash escaped: {{literal_braces}}

Raw block:

{{not_a_variable}}
{{another_raw_thing}}


Normal variable: escaping-test
