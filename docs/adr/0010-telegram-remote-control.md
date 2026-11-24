# 0010. Notifications and replies over Telegram

- Status: Accepted
- Date: 2026-11-18

## Context and problem statement

This record was written retroactively, on 2026-11-24. The original text of ADR-010 is not in this repository; the
decision is reconstructed from the changelog (version 1.11.0 and the Telegram entries that follow it) and from the
header of `ws-telegram`, whose security section names this ADR. The date is the release date of version 1.11.0.

Claude stops and waits when it asks for a decision or finishes a long turn. Answering from a phone means sending keys
to a tab from outside the machine, so the channel is defined by what it must prevent: someone else writing to the bot,
a late or repeated tap, a dialog that changed in the meantime, arbitrary text reaching a tab, and screen text with
secrets leaving the machine.

### Later changes

- Later versions added proposed `!` commands with a run button (1.16.0), text replies protected by a PIN (1.18.0) and
  alerts with a daily summary (1.21.0).
- [ADR 0013](0013-minimum-protection-floor.md) tightens the channel: commands are not offered or run in tabs without a
  sandbox, a second block list applies, and running a command asks for the PIN.

## Decision drivers

- The user must be able to answer Claude without being at the PC.
- Only the owner may act through the channel.
- No secret may leave the machine in a message, and the bot token must not be readable from a file or a command line.
- A tap must never send something to a dialog that is no longer the one shown.

## Considered options

The alternatives weighed when the decision was made are not recorded in this repository. The implemented option is the
one described under Decision.

## Decision

Send Claude's notifications over a Telegram bot and accept answers through buttons (`ws-telegram`). A notification
arrives when Claude asks for a decision or finishes a long turn, with the question redacted and one button per option
plus cancel; the answer is sent to that tab.

Security rules of the channel:

- The token lives only in the Windows Credential Manager (`ws-secret`); it is never in files or on `curl`'s command
  line (it goes through a file descriptor).
- Only buttons from the owner's chat are handled; the chat id is fixed at setup.
- Each notification carries a single-use code that expires in 10 minutes.
- Before sending the key, the screen is read again: if the dialog changed, nothing is sent.
- There are only closed options (a number or Escape); never free text.
- The screen text is redacted (tokens, keys, passwords) before it leaves the PC.
- Everything is logged in `~/.local/share/ws-telemetry/telegram/`, without the screen text.

The channel is optional and is set up with `ws-telegram setup`; the menu and `ws-telegram on`, `off`
turn it on and off, and `ws-telegram forget` deletes token, chat and state.

## Consequences

- Positive: a waiting tab can be answered from the phone, with the same options the dialog shows.
- Positive: the channel cannot inject arbitrary text, because buttons carry closed options only.
- Negative: the Telegram Bot API is a third party; notification text, after redaction, is stored by Telegram.
- Negative: redaction is pattern-based; a secret with an unrecognized shape is not masked.
- Negative: an unlocked phone is the owner.
