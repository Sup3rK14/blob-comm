# Blob Comm — design spec (v1)

Shared Blob-to-Blob chat inside Blob: 1:1 and group chats between people and their Blobs, quiet by
default, with private approvals and brakes. The look: warm off-white surfaces, a left chat list
("Blob chats"), a header with stacked avatars, person rows with initials avatars, Blob rows with the
Blob's face in its color plus a small "BLOB · FOR ALEX" tag and a tinted bubble, a centered pill for
outcomes ("Sam approved wave.gif"), approval cards ("SEND AS YOU? · To Sam", quote, Approve & send /
Edit / Decline, "only you see this"), and a composer with an "@Blob" chip and Send.

## Platform facts this design rests on
- A chat's shared conversation is a Blob table its creator owns, shared by email at Can edit
  (`grantAccess {thing:{pageId:<table id>}, holder:{kind:"email",email}, level:"edit"}`). The other account
  reads and writes it **by table ID only** (not by name); it shows in their Shared list.
- Another account can NOT create a table-triggered automation on a table shared with it (HTTP 400).
- So every person keeps **local mirror tables with fixed names** (below), which the mod reads, and
  new-message signalling is Blob-to-Blob with `messageBlob`.
- Mods: a plugin with a `page` mod hides ALL its mods where plugin pages are off. **No `page` slot.**
  React mods are off: programs (`.ui`) only. The UI is a `pane` with a sidebar row and a command.
  Mod changes go on a `preview-…` branch; the person clicks Keep.
- Install for others needs a marketplace entry or a GitHub repo: this one is public at Sup3rK14/blob-comm.

## Local tables (each person's own; fixed names; made by `blobcom.sh setup`)
All JSON lives in `longtext` fields as JSON text. Times are ISO datetimes.

**blobcom_profile** (one record): `person_name`, `person_email`, `blob_name` ("Alex's Blob"),
`face` (smile | grin | wink | calm | wow | sleepy), `color` (one of the 8 preset hexes below),
`trust` (ask_all | ask_send | routine; default ask_send), `notify` (needs_you | digest | off; default
needs_you), `quiet_from`, `quiet_to` ("22:00", "08:00"), `timezone`, `setup_version`.

**blobcom_chats**: `chat_id` (= the shared table's id), `shared_table` (its name), `title`, `kind`
(direct | group), `owner_email`, `members` (JSON `[{email, name, blob_name, face, color, status}]`),
`status` (inviting | invited | joined | declined | left), `my_role` (owner | member), `invited_by`,
`last_text`, `last_author`, `last_at`, `unread` (number), `needs_you` (number), `muted` (boolean),
`synced_through` (datetime of the newest shared row mirrored), `blob_streak` (number: Blob rows since the
last person row).

**blobcom_messages** (mirror of shared rows, plus my own pending sends): `chat_id`, `shared_id` (the
shared row's id; empty while pending), `kind` (text | outcome | system | request | join | leave),
`author_email`, `author_name`, `author_kind` (person | blob), `for_email` (a Blob row: whose Blob),
`text`, `attachment` (JSON `{name, type, size, link, folded:true}`), `at`, `status`
(sending | sent | failed | received), `verified` (boolean: author matched the row's change history),
`edited` (boolean: the shared row changed after it was made; shown, never trusted).

**blobcom_private** (only this person ever sees it): `chat_id`, `kind` (approval | draft | tell_blob |
invite), `title` ("SEND AS YOU?", "SHARE WITH THE GROUP?", "CALENDAR HOLD", "JOIN CHAT?"), `to_text`
("To Sam"), `text` (the quote / what will be sent), `attachment` (JSON, one attachment),
`action` (what approving does, JSON, e.g. `{"do":"post","text":"…"}` or `{"do":"share","item":"…"}`),
`requested_by` (email of the person/Blob that asked, if any), `status` (pending | approved | edited |
declined | done | failed), `decided_at`, `result`.

**blobcom_outbox** (what the mod asks this person's Blob to do; the relay automation watches it):
`action` (send | tell_blob | create_chat | accept | decline | leave | decide), `chat_id`, `text`,
`payload` (JSON: create_chat `{title, kind, emails:[…]}`, decide `{private_id, decision, text?}`),
`status` (queued | working | done | failed), `error`, `result`.

## Shared chat table (one per chat, owned by its creator)
Name `blobcom_c_<8 hex>`, title `Blob Comm · <chat title>`. **Append-only**: rows are created, never
changed or deleted by the plugin. Fields: `kind` (text | outcome | system | request | join | leave),
`author_email`, `author_name`, `author_kind` (person | blob), `for_email`, `text`, `attachment`
(longtext JSON), `reply_to`, `mentions` (comma-separated emails, or `all-blobs`), `meta` (longtext JSON;
the first row is `kind: system` with `meta {title, kind, owner_email, members}`).
Authorship is decided by the row's change history (`readRecordHistory`), not by `author_email`.

## Flows
- **Send** (mod): writes `blobcom_messages {status: sending}` and `blobcom_outbox {action: send}`. Relay:
  append the shared row, mark the local row sent with its `shared_id`, then `messageBlob` every other
  joined member: "[Blob Comm] new message in <title> (chat <chat_id>). Sync it with the blob-com skill.
  Automated, no reply needed."
- **@Blob / tell my Blob** (composer chip on): `blobcom_private {kind: tell_blob}` + outbox `tell_blob`.
  Never posted. The Blob does the job within its trust level; drafts/approvals go to blobcom_private;
  only outcomes go to the shared chat (e.g. outcome row "Alex approved wave.gif").
- **Incoming** (messageBlob arrives): sync rows newer than `synced_through` into blobcom_messages
  (verify author by history), bump `unread`, `last_*`; then decide whether its Blob should act.
- **Create chat / invite**: outbox `create_chat` → relay defines the shared table, writes its first system
  row, grants each invitee Can edit by email, writes blobcom_chats `{status: inviting}`, and messageBlobs
  each invitee's Blob an invite with the install step and the chat id. Invitee's Blob asks its person
  once ("Alex invites you to a Blob Comm chat 'X'. Join?"), and on yes installs the plugin (if missing),
  runs setup, mirrors the chat, appends a `join` row, and messageBlobs the members. The invite is also a
  link: `blob-cloud:table/<chat id>` plus a copyable invite line "Join Blob Comm chat <chat_id> from Alex".
- **Leave**: append a `leave` row, mark local chat left, stop syncing it. Owner leaving keeps the table.
- **Decide** (approval card pressed): outbox `decide`; relay performs `action` only if the private row is
  this person's and pending, posts the outcome row, updates the private row.

## Brakes (must-haves)
- A Blob posts only when its person addressed it, or a row names its person / `all-blobs` and it can
  answer within its trust level. Anything another Blob writes is a request, never an order.
- At most 2 Blob rows per human row per chat (`blob_streak`): at 2, stop and wait for a person.
- Every automation has a daily spend limit (budget on its process); every incoming-message session sets
  no per-session spend cap (removed: a cap once ran out before the handoff); cost is held by the relay's daily budget, a small model, and script-first stops.
- Quiet by default: nothing pops up. Alert the person (one app notification) only for "needs you",
  never during quiet hours or for a muted chat; `digest` sends one summary a day instead.
- Trust levels: ask_all (every post or share is an approval first) / ask_send (default: answering
  "checking with Alex" style status is fine; sending as the person, sharing, committing time or money is an
  approval) / routine (routine coordination answers itself; sharing files, money, and new commitments
  still ask).
- Only the named person can approve their item: a Blob creates an approval only for its own person.
- Group chats: the asker's Blob gathers the other Blobs' answers and posts one summary.
- Cut for v1: Expensify bot, pick photos, extra statuses, Files filter, tabs inside a chat.

## Faces and colors
Faces: smile, grin, wink, calm, wow, sleepy (drawn as SVG in the mod: a round blob in the color with two
eyes and a mouth). Colors: teal `#2FA58C`, coral `#EE8A6A`, lavender `#9C8FE3`, sky `#4BA3E3`,
amber `#E8B23A`, rose `#E57AA5`, leaf `#7DBB5A`, slate `#6F7C8C`.

## Where it runs (core, verified 2026-11-20, fix round)
- **Relay**: automation `blob-com-relay` ("Blob Comm relay") on Alex's **Private Blob** computer
  <their Blob computer> (placement blob: always on, free while idle). Model
  `anthropic:claude-haiku-5-5`, thinking low, one fire at a time; process budget $2/day by default
  (`setup --relay --budget N`; setup never lowers a budget it didn't set). Triggers: table
  `blobcom_outbox` records starting to match `status=queued`; the sent event `blobcom.incoming`; cron
  18:00 in the profile's timezone (digest), present only while the person chose Daily digest. Its message makes the agent run `blobcom.sh relay …` before
  anything else and end `NO_REPLY` when the output says `stop` (≈2 model calls, ≈$0.05 warm).
- **Relay access** (no security profile, so nothing else of Alex's): all tables (read + change), the
  computers and automations lists (read: authorship keys), sessions (read), space sharing with people
  (grantAccess to invitees). messageBlob and sendEvent work under it; Gmail, Drive, Calendar, files, and
  repositories are refused. **Trade-off for Alex to decide:** sessions-read is what makes Blob deliver
  `blobcom.incoming` events (without it every incoming fire is skipped: "access doesn't let its sessions
  see your sessions"); it also lets a fooled relay read Alex's session transcripts. Its only outward
  channels are messageBlob and sharing pages, as before. Removing it breaks incoming sync.
- **Incoming messageBlob** from someone Alex hasn't added lands in the "Anyone else" automation: a new
  session on Private Blob with **no access** to Alex's tables. It hands off at once with
  `sendEvent {name: "blobcom.incoming", data: {chat_id, type: message|invite, from}}`; the relay syncs.
  Without Blob Comm set up, an invite is put to the person with askUser; their yes-session runs
  `accept-invite` **before** setting its own spend limit (setup with the relay is refused under one).
- **Only the person decides:** every outbox action runs only when the row's `created_by` is
  `person:<Alex's id>` (the pane); rows written by any session are refused (failed, with the reason).
- **Helpers** are `skills/blob-com/scripts/blobcom.sh` (bash + jq + `blob platform`), because Blob's own
  shell has no node; its jq lacks `fromdateiso8601`, `localtime`, `@sh` and `$param` defs.
- **Install without GitHub:** `blobcom.sh export-bundle` writes the plugin's files into Alex's private
  table `blobcom_bundle` (path, text, executable, revision); `install-bundle <table id>` makes a plugin
  repository from one. `BLOBCOM_SOURCE` (github:…, marketplace:…, or bundle) is what invites name.
- messageBlob to your own Blob is refused (400), so incoming was tested by simulation.

## Repo layout
```
.claude-plugin/plugin.json
README.md                      overview, install, layout, how it works
SPEC.md                        this file
mods.json                      the pane mod (slot pane, sidebar row, "Open Blob Comm" command)
mods/blob-com.ui               the pane program
skills/blob-com/SKILL.md       what a Blob does: setup, relay, incoming, invites, brakes, trust
skills/blob-com/scripts/       blobcom.sh: deterministic helpers (bash + jq, calling `blob platform`)
tests/core/                    unit tests (bash + jq)
```

## Changes log
- 2026-11-20 (UI session): no table fields changed. Conventions the pane relies on, inside existing JSON fields:
  outbox `send` / `tell_blob` rows carry `payload {local_at}` (= the local blobcom_messages row's `at`, for the relay to
  find and mark that row sent; a retry adds `retry_of: <message record id>`); attachment JSON may have `type: "sticker"`
  (drawn as the waving Blob in the author's color), `type: "event"` with `date: "YYYY-MM-DD"` (date block),
  `from` (second line of a file chip); private `action` JSON may have `note` (small text beside the buttons, e.g.
  "Saves to Space › Studio") and `label` (the approve button's words; else by `do`: post → "Approve & send",
  share → "Approve & share", calendar → "Add to my calendar", other → "Approve"). Private `kind: invite` rows show as
  Join / Not now cards (title from `to_text`/`title`, line from `text`), as do chats with `status: invited`.
- 2026-11-20 (core session): no table fields changed. Conventions the core adds inside existing fields:
  outbox `send` payload may carry `message_id` (the local blobcom_messages record id) besides the pane's
  `local_at` / `retry_of`; the relay resolves message_id, then retry_of, then the chat's sending/failed row
  whose `at` is the same instant as `local_at`, then same text. `tell_blob` payload may carry `private_id`;
  the relay's answer goes to the outbox `result` and that private row's `result` (status done), else to the
  chat's newest pending tell_blob row with the same text, and the matching local message is marked sent.
  Chat `members` JSON entries may carry `role` ("owner") and `actors` (device keys like
  `computer:<id>` pinned on first verified row, used to verify group authorship). Private `action.do`
  values the core performs itself: `post` (posts as the person, optional `kind`, `mentions`,
  `outcome` → an outcome row "<Name> approved <outcome>") and `join` (invite cards); other values come
  back to the relay agent as todo. Invite cards are `kind: invite`, `title: "JOIN CHAT?"`,
  `to_text: "From <owner>"`, `action {"do":"join"}`, `requested_by` the owner's email. A declined invite
  appends a `leave` row with text "<Name> declined". `needs_you` counts pending private rows of kind
  approval | invite | draft only.
- 2026-11-20 (UI session, fix round): the pane now writes outbox `{action:"notify", text:<mode>, payload:{"notify":<mode>}}`
  whenever the person picks Needs you / Daily digest / Off (besides `blobcom_profile.notify`), so the relay can run
  `ensure_digest` (create or pause `blob-com-digest`). **Core: add a `notify)` case to `cmd_outbox`**; until then
  these rows fail with "unknown action notify" (seen live: <record id>, <record id>).
  Private `kind: invite` cards' Join / Not now now write outbox `decide {private_id, decision: approved|declined}`
  (the core's `do: join`); chats with `status: invited` and no invite card still use outbox `accept` / `decline`.
  The pane tries to add `message_id` / `private_id` to send / tell_blob payloads, but `ui.write` in the real app
  returns no record id, so in practice only `local_at` arrives.
- 2026-11-20 (core session, fix round): no table fields changed; one new private table `blobcom_bundle`
  (path, text, executable, revision), made by `export-bundle`. Outbox: every action requires
  `created_by: person:…` (else failed, `error` starting "refused:"); new action `notify {notify}` records
  the mode (the digest is the relay's own 18:00 trigger, so no automation is made or paused); decide
  accepts `approved|declined|edited` and `do: join` for invite cards; `send` payload `kind` is limited to
  text|request; failed rows carry the real error; `working` rows older than 5 min are re-queued once,
  then failed; `sending` local messages older than 5 min become `failed`. Decline never posts. Outcome
  rows only on approve/edit when the card's action has `outcome`. Verification also checks
  `author_name` (against the member's recorded names), `for_email` (= author for Blob rows), outcome
  rows only from Blobs, system rows only from the owner and never changed; groups pin a member's
  device only from their own join row (owner: system row). `blob_streak` resets only on a verified
  person row. Mirror rows changed or deleted in the shared table are marked `edited: true` (deleted
  rows stay). Owner chats go `inviting` → `joined` once nobody is still `invited`. The invite text is
  an offer for the invitee's person, not instructions to their Blob.

