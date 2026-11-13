---
name: merge-request
description: Open a merge request or pull request, or write its description. Use for "open an MR", "create a PR", "write the MR description", "push this branch and open it for review", or rewriting a description that reads as agent slop.
---

# Merge Request

- **Opener** — one to three sentences at the top, in the voice of the person opening the MR,
  saying whether this deserves the reviewer's attention and what to look at. Editorial
  judgement, not a second summary: "one-line config fix, skim it" and "this changes how
  sessions expire — look at the cache path" both do the job. A sentence from the description
  below is often the right opener; lift it. A screenshot sits well here when the change is
  visual.
- **details-summary** — everything else goes inside a collapsed block, labelled with the
  model that wrote it. Say "details-summary" aloud to keep the order straight: `<details>`
  wraps, `<summary>` is the clickable line.

Use this template for the merge request body:

```markdown
<opener: 1-3 sentences, plain voice, why this matters or what to look at>

<optional: screenshot>

<details>
<summary>Full description — <model name and effort></summary>

< the full MR description here >

</details>
```

The blank line after `<summary>` and before `</details>` is important: without it, GitLab and
GitHub render the markdown inside as literal text. Talk in ASD-STE100 Simplified Technical
English.
