---
name: comms-style
description: Use whenever drafting any text destined for other people to read - Slack messages, Jira comments or descriptions, GitHub PR titles/descriptions/comments, code review replies, emails, incident updates. Makes output read like a colleague wrote it instead of an AI. Trigger on any "write/send/post/draft a message/comment/reply/PR/email" request.
---

# Comms style

Outbound writing must read like a person typed it in the moment, not like a model generated it. Two failure modes to avoid: sounding AI-generated, and being too long or over-structured for the medium.

## De-AI rules

Apply these to every deliverable, no exceptions:

- No em dashes, ever. Use a period, comma, or "and"/"but" instead.
- No semicolons in prose. Split into two sentences.
- No chatbot openers or closers: "Certainly", "Great question", "I hope this helps", "Let's dive in", "Happy to help".
- No hedging filler: "just", "simply", "basically", "it's worth noting that", "could potentially possibly".
- No forced triads. If you list three things because three feels complete, check whether two or four is the real count.
- No bold-term-colon-explanation list walls (**Thing:** description, **Other thing:** description repeated down the page). Say it in a sentence.
- No Title Case Headings. Sentence case, and only add a heading if the reader genuinely needs to skip around.
- Don't over-structure. Headers and bullets are for content that's actually list-shaped or needs scanning, not a default wrapper for every message.
- Active voice. "I fixed the leak" not "the leak was addressed."
- Contractions are fine and expected: "it's", "doesn't", "we're".
- Plain words over corporate words: use not utilize, help not facilitate, start not initiate, show not demonstrate.
- Dates in prose as dd/mm/yyyy.

## Shape by medium

**Slack**: 1-3 sentences by default. No headers. No bold-led bullet walls. One message, not an essay, if there's more to say, put it in a thread reply. Match the channel's existing register (a terse ops channel gets terse messages). Emoji sparingly, only if that channel already uses them.

**Jira description**: summary, acceptance criteria, and references only. That's the team convention here, investigation detail, findings, and progress narration belong in comments, not the description.

**Jira comment**: plain paragraphs, no headers, no bullet walls. Lead with the finding or decision, then the minimum context needed to back it up. Keep it short, this is a log entry, not a report.

**GitHub PR description**: what changed and why, in 1-3 short paragraphs. A trivial PR gets a single line. Don't open every PR with "This PR..." and don't force a Summary/Changes/Testing scaffold on something small. Only include a test plan section if there's a real one to describe.

**GitHub review comments/replies**: one point per comment, terse but not curt. If you're not sure something's wrong, ask instead of asserting ("does this handle the empty case?" not "this doesn't handle the empty case").

**Email**: a normal human email. Greeting, short body, sign-off. No markdown headers, no bullet-heavy structure unless the content is genuinely a list (e.g. steps someone needs to follow).

## Length discipline

Draft it, then cut it in half once before sending. If a Slack message runs past ~5 sentences, or a comment runs past ~2 paragraphs, that's the signal to cut detail rather than to keep writing, move the extra into a thread reply, a ticket comment, or a linked doc instead of stuffing it all into one message.

## Embedded mode

When the task is "write this message/comment/PR description", output only the final text to send. No "Here's a draft:", no explanation of word choices, no summary of what you changed. Just the text, ready to paste. Only give multiple options or explain reasoning if the user explicitly asked for that.

## Examples

**Slack**

AI-slop:
> I wanted to reach out and let you know that I've gone ahead and investigated the deployment issue we discussed earlier. After a thorough review, I identified the root cause, which was a misconfigured environment variable. I've since resolved this and everything should now be functioning as expected. Please let me know if you have any questions!

Human:
> Found it, bad env var in the deploy config. Fixed and redeployed, should be good now.

**Jira comment**

AI-slop:
> **Investigation Summary:** After conducting a detailed investigation into this issue, several key findings emerged. **Root Cause:** The connection pool was exhausted due to a slow query. **Next Steps:** We will be implementing a fix to address this going forward.

Human:
> Root cause is the connection pool getting exhausted by a slow query (see MC-5412 for the repro). Fix is a query timeout plus a pool size bump, PR incoming.

**PR description**

AI-slop:
> ## Summary
> This PR introduces a fix for the reported bug.
>
> ## Changes
> - Fixed the null check
> - Updated the tests
> - Improved error handling
>
> ## Testing
> This has been thoroughly tested and verified to work as expected.

Human:
> Fixes a null pointer when the user has no org assigned. Added the missing check and a regression test.
