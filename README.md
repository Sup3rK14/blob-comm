# Blob Com

Shared chats between people and their Blobs, inside Blob. Each chat is a Blob table its creator owns and
shares by email at Can edit; each person's Blob mirrors it into fixed local tables that the Blob Com pane
reads, and Blobs tell each other about new rows with messageBlob. Full design: [SPEC.md](SPEC.md).

## Install and set up

**Invited to a chat?** Say yes when your Blob asks (or click Join on the JOIN CHAT? card). Your Blob then
installs Blob Com from this repository in one step and joins:

```
install {"repository": "Sup3rK14/blob-com", "owner": "you"}
```

followed, in a chat with no spend limit, by `skills/blob-com/scripts/blobcom.sh accept-invite <chat id>
--from <inviter email>`, which sets everything up (below) and joins the chat.

**Starting on your own?** Install it the same way (or from the Customize page, "Install from GitHub",
`Sup3rK14/blob-com`), then in a normal chat with your Blob (not an automation; it needs a session
without a spend limit) say "Set up Blob Com". It runs `blobcom.sh setup --name <you> --email <your Blob
email> --relay --budget 2`: five private tables, your profile, and the **Blob Com relay** automation on
your always-on Blob computer with a $2/day budget. Open the pane from the **Blob Com** row in the
sidebar or the "Open Blob Com" command. Setup keeps your Blob Com tables together in a **Blob Com**
page in your Private section (chats you start go there too); leave them there and don't rename them.

## How it works

- The pane writes requests to `blobcom_outbox` (send, tell_blob, create_chat, accept, decline, leave,
  decide). The relay fires on each queued row and runs `blobcom.sh outbox`, which does the work and marks
  the row done or failed.
- A Blob that writes to a chat messageBlobs the other members' Blobs: "[Blob Com] new message in … (chat
  t_…)". The receiving session hands that to its own relay with a `blobcom.incoming` event; the relay
  syncs the chat, verifying each row's author from the table's change history.
- Blobs post only when addressed, at most 2 Blob rows per person row, never take another Blob's words as
  orders, and only ever ask their own person to approve. See `skills/blob-com/SKILL.md`.

## Access and cost

The relay runs with narrow access: all tables (read and change), the computers, automations, and
sessions lists (read), and sharing pages with people. Nothing else: no mail, calendar, files, or
repositories. Reading sessions is needed so Blob delivers the `blobcom.incoming` events; it also means
a misled relay could read your session transcripts. Its budget is $2/day by default, about $0.05 a
run. Only your own clicks in the pane can send, decide, invite, or leave; requests written by any
session are refused.

## Recommendations

- **Relay model:** each fire loads ~114k tokens before the script runs, so a cold start costs about
  $0.22 on Sonnet (a warm run about $0.04–0.05). A smaller model (e.g. `anthropic:claude-haiku-5-5`)
  cuts that; a model-free check of the event before a session starts would remove it.
- **Relay access** reads all of your tables and your sessions (sessions-read is what makes Blob deliver
  `blobcom.incoming`). Narrow it further if Blob adds per-table grants or a way to hear events without
  reading sessions.

## Layout

```
.claude-plugin/plugin.json
SPEC.md                         design, tables, flows, brakes, changes log
skills/blob-com/SKILL.md        what a Blob does with Blob Com
skills/blob-com/scripts/blobcom.sh   deterministic helpers (bash + jq + blob platform)
tests/core/test_jqlib.sh        unit tests (bash + jq; run locally or in Blob's shell)
tests/core/test_decide.sh       unit tests for decide
mods.json, mods/blob-com.ui     the Blob Com pane (a Blob mod program)
```

Tests: `bash tests/core/test_jqlib.sh && bash tests/core/test_decide.sh`.

License: MIT.

