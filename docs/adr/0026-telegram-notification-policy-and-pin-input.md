# 0026. Telegram notification policy (approvals, digest, quiet hours) and PIN input that just works

- Status: Accepted
- Date: 2026-11-26

## Context and problem statement

Referred to in code and changelog as ADR 0026. It amends [0010](0010-telegram-remote-control.md) (the channel) and
keeps every rule of [0013](0013-minimum-protection-floor.md) (PIN for ▶ Run and risky approvals).

The owner's Telegram event log (`~/.local/share/ws-telemetry/telegram/*.jsonl`, metadata only) for 18–26 Nov 2026
showed two problems.

**The PIN looked broken, although it worked.** `approve_asks_pin` → a Reply to the "send your PIN" prompt →
`approve_authorized pin` succeeded every time. Everything else failed, silently or wrongly:

| Evidence (26 Nov, 04:12–04:15 UTC) | Cause in `ws-telegram` |
|---|---|
| `message reply_to=none length=6` → `text_no_target a=none` | A PIN sent as a new message went down the text-reply path, which needs a Reply. The PIN stayed in the chat (the text path deleted nothing). |
| `message reply_to=2920 length=6` → `pin_wrong 1` and "🚨 Wrong PIN in a text reply" | A bare PIN as a Reply to the **dialog alert** (not to the prompt) went down the text path, which expects "PIN space answer": a correct PIN was counted as wrong, alerted, and moved the 3-strike counter that turns text replies off. |
| `message reply_to=2938` right after `approve_authorized` → `text_no_target a=2938` | After a correct PIN only the dialog alert, far up the chat, was edited; the prompt the owner was looking at did not change, so the PIN was sent again — and left in the chat. |
| `text_rejected dialog with options in %22` | Text sent to a tab showing a dialog: refused with a message that did not say what to do instead. |
| (code review) `PIN="$(pin)"` once at service start | If Windows interop was not ready when tmux started the service, the PIN stayed empty for the life of the service and every 🔐 said "none is set". |
| (code review) the text path ignored the emergency stop marker | A text reply could still reach a tab while `ws-stop-all`'s marker existed (only buttons and ▶ Run checked it). |

**Telegram was noisy.** 983 messages in 8 days. The same "🧠 Context at 85% in 14 eureka-tenant" 23 times (every
30 minutes, all night: the alert was rate-limited, not deduplicated); "⚠️ Claude usage at 9x%" every hour (its key
contained the hour, so the 120-minute limit never applied); 43 "💸 High usage" alerts; 120 "⏰ still waiting"
reminders (every 3 minutes); 356 "finished" notices. Twenty `error_api` entries, 19 with an empty detail: `curl`
returned nothing (no network, after sleep or a network change; 40 s apart = curl's 30 s timeout + a fixed 10 s sleep)
and the code logged only Telegram's `description`, which does not exist without a response; one was
`Too Many Requests: retry after 5` during a burst of 19 messages in a minute. The owner asked for "only the approvals
that are needed, or a session summary every X time".

## Decision drivers

- Keep every security property of the channel: only the owner's chat, PIN deleted from the chat, 5-minute expiry,
  single use, 3 wrong PINs in 1 h cancel, the dialog re-read before the key is sent, the audit hash chain
  (WS-AI-007, WS-SEC-011), the emergency stop (WS-AI-025).
- Approval fatigue (WS-AI-006, OWASP ASI09): fewer, more meaningful interruptions make each approval worth reading.
- Never silent: a message the bot does not act on must say why and what to do.
- No conversation text or secrets in anything new that leaves the machine.

## Considered options

PIN input:

- **A. Keep "Reply to the prompt" only, with better messages.** Smallest change; still fails the two most natural
  gestures (a new message, a Reply to the alert).
- **B. Accept a bare PIN for the pending request.** With one request pending, a bare PIN (4–6 digits, or "pin 1234")
  as a Reply to any of its messages or as a new message; with several, the Reply decides and the bot says so.
- **C. An inline numeric keypad.** The digits travel as `callback_data` and do not appear in the chat history.

Notifications:

- **D. Rate limits per alert, tuned.** Keeps the volume; still a message per event.
- **E. A policy with classes, a digest and quiet hours.** Only what needs the owner goes at once; the rest is
  summarised.

## Decision

Options **B** and **E**. C is documented and not built (see below).

### PIN input (B)

- A bare PIN is recognised first (`BARE_PIN_RE`) and handled by `handle_pin`; it is **never** routed to the text
  path and never counted as a wrong text reply. The message is deleted first, whatever happens.
- Target: the request whose prompt or notification was replied to; otherwise, with exactly one live request, that
  one; with several, nothing is done and the answer asks for a Reply to the 🔐 message meant. A PIN followed by words
  as a Reply to a request counts as the PIN; words without a PIN get the exact format.
- Only a PIN for a real request counts as wrong; 3 wrong in 1 h cancel every request (unchanged). Expired requests
  and used requests ("already done at 04:14") are answered as such, not counted.
- After the PIN the outcome is written on the prompt too (`✔ PIN accepted: approved 1 · Yes`), not only on the alert.
- The PIN is read lazily (`load_pin`): if the first read fails it is read again when needed (at most once a minute),
  and the reason is kept — "no PIN is set" (ws-secret exit 3) or "the Windows Credential Manager did not answer
  (interop not ready?)" — for the answers and `ws-telegram status` ("PIN in the service: yes/no"). The status file
  never holds the PIN.
- Every message that is not acted on gets a short answer (`say`), rate-limited (the same reason once per 20 s, 30 an
  hour). A stranger still gets nothing; the owner gets a security alert. The emergency stop now covers messages too.

### Notification policy (E)

Every outgoing message has a class, and `route` decides now / digest / drop:

| Class | Examples | `approvals` (default) | `digest` | `all` | `off` | Quiet hours |
|---|---|---|---|---|---|---|
| sec | someone else, wrong PINs, anomalies, bad kit signature | now | now | now | now | now |
| approval | permission dialog, PIN prompt, routing question | now | digest | now | drop | now (not in `digest`) |
| blocked | open question, `!` command, "run this / let me know", Claude stopped | now | digest | now | drop | digest |
| direct | `ws-notify --telegram`, `ws-telegram send`, `test` | now | digest | now | drop | digest |
| info | finished turns, context, usage, stalled, budgets, backups, CI, weekly | digest | digest | now | drop | digest |

- `ws-telegram notify approvals|digest|all|off`, `digest 30m|1h|2h|4h|off|now` (default **1h**, the owner's choice),
  `quiet HH:MM-HH:MM|off` (may cross midnight). Settings live in the guarded `~/.config/ws-telegram/settings`; each
  change is logged and audited (`setting_changed`); the menu shows the current values.
- **Digest**: one message per period, only if something changed (a new event, or a tab that opened, closed or changed
  state or context in steps of 5 %), never in quiet hours: per Claude tab its name, project, state
  (working / waiting for you / idle, from `@cphase`), context (`@cctx`), cost (`@ccost`, from the status line) and
  its last notable event; events of no tab ("elsewhere"); counts. A 🔎 button per tab (read-only, may be pressed
  again during the period) answers with `tmux-summary --text` metadata lines (folder, branch, state, turns) — never
  the prompts or answers. Events are the kit's own one-liners (`✔ finished in 3m 2s`); conversation text never
  enters the digest buffer. Everything is redacted with the kit's `redact`. In `all` the digest only carries what the
  quiet hours held; the daily summary is sent only in `all`.
- **Deduplication**: the context alert and the plan-limit alert fire once per threshold crossing (re-armed 10 points
  below, e.g. after `/compact`); stalled, usage and error alerts at most once per `dedup_hours` (6) per tab; a single
  reminder of a waiting dialog after `remind_min` (5) minutes instead of every 3 minutes.
- **error_api**: `api()` keeps curl's exit code and the HTTP status (`curl -w`), logs the reason (`network: no answer
  within 30 s (curl 28)`, `HTTP 429: Too Many Requests…`, `HTTP 502: Bad Gateway`; never the URL, which holds the
  token), writes it to `$ST/last-error` for the status, and the polling backs off: `retry_after` + 1 for a 429;
  5, 10, 20 … 300 s for network errors and 5xx; 60 s for 409; 300 s for 401. A 429 on a send holds the rest of the
  queue for the time Telegram asked.
- Claude cannot change the policy: the settings file is a protected path (guard.sh, deny `Edit(~/.config/ws-telegram/**)`),
  and `ws-telegram notify off|approvals|digest`, `quiet`, `digest off`, `off`, `text off` are ask rules. The tmux
  menu (Menu → Workstation → Telegram) runs outside Claude; the PIN is typed only in a terminal popup.

### The inline keypad (C), not built

Honest evaluation: callback data does not appear in the chat history, which is an advantage over a message that is
deleted a second later. But the digits still reach Telegram's servers exactly like a message; a fixed layout lets
anyone who sees the screen read the PIN from the taps (Telegram highlights the pressed button), and a shuffled layout
costs usability; the partial PIN must be kept between updates (on disk, or only in the service's memory, lost on
restart); and it adds code to the authorisation path. A typed PIN that is deleted at once, with the fixes above, solves
the reported problem. If it is built later it must stay off by default, shuffle the layout per request, keep digits in
memory only and count a wrong PIN the same way.

## Consequences

- Positive: a correct PIN works with the gestures people actually use, is never punished as wrong, and never stays
  in the chat; the bot always answers. The PIN survives a slow Windows start.
- Positive: from ~120 messages a day to the approvals that block work, security alerts and one digest an hour at most
  (only when something changed); quiet hours for the night.
- Positive: `error_api` entries say what failed and the service no longer polls a dead network every 40 s.
- Negative: in `approvals` mode, finished turns and context alerts arrive up to an hour late (in the digest); a
  finished turn that ends with a request the detectors miss is not sent at once (use `notify all`).
- Negative: a bare PIN with one request pending authorises that request even if sent as a Reply to an unrelated
  message; acceptable because the owner started the request with a 🔐 tap and the PIN is still required.
- Negative: more state in `~/.local/state/ws-telegram` (digest buffer, crossing markers, say rate limits); all
  metadata, cleaned on schedule.
