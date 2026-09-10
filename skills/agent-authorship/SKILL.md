---
name: agent-authorship
description: Identify AI-authored GitHub issues, pull requests, reviews, and comments with the agent name and model. Use whenever an agent creates, edits, or submits repository-hosting content on the user's behalf. Not for commit messages, code comments, or chat replies.
---

# Identify agent-authored repository messages

Add this footer to every issue body, pull-request body, review, and comment that you write
or materially edit on the user's behalf:

```markdown
---
Written by <agent name> using <model identifier>.
```

Use the agent or product name shown by the current runtime, such as `Codex`, `Claude Code`,
`GitHub Copilot`, or `OpenCode`. Use the exact model identifier or model name supplied by
the runtime. Do not infer a model from the agent name, vendor, or apparent capabilities. If
the runtime does not expose the model, write `an unavailable model identifier` in its place.

Keep the footer separate from the message body. Add it before submitting the content, even
when the repository platform will post through the user's account or already displays a bot
badge. When updating an agent-authored message, update the footer if the current agent or
model differs. When making a material edit to an unsigned message on the user's behalf, add
the footer so the resulting content does not appear solely human-authored.

Do not add this footer to text written entirely by the user, quoted third-party text, commit
messages, source-code comments, generated files, or private chat responses. Do not claim a
different agent or model at the user's request; authorship metadata must stay factual.
