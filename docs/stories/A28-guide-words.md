# A28: the guide says one bot per hub, and never to paste a key into a chat

Status: **Approved** (owner, 2026-11-28: "Approve as written"). Risk: **low** (screen copy only; the token prompt and
every key path are unchanged).
Verification: `bash tests/run.sh`.

## Today and the gap
The set-up guide (`ade setup`) asks for a Telegram bot token at step 7 without saying a bot belongs to one hub, so a
person with two hubs may reuse a bot. Step 2 offers an API key without saying where a key never goes: a chat.

## Approved text (exactly as written)
1. The Telegram step's explanation (`guide_about telegram`, "Step 7 of 7") adds:
   "One hub, one bot: each hub gets its own Telegram bot."
2. The key step (Step 2, beside the API key option) adds:
   "Never paste a key into a chat; a current hub stops it and tells you where it goes."
   At 80 columns it wraps after "tells you", like the other explanation lines.

## Acceptance criteria (tests in `tests/test_guide.sh`)
1. **tg_one_bot**: the guide's Step 7 explanation shows "One hub, one bot: each hub gets its own Telegram bot."
2. **key_no_paste**: the guide's Step 2 explanation shows "Never paste a key into a chat; a current hub stops it and
   tells you where it goes." before the sign-in options.
3. **guide_happy_path**: `tests/golden/guide-80.txt` gains only these lines, and every line stays within 80 columns.

## Out of scope
The ade-drill goldens (a separate change in ade-drill); the token prompt and its logic (`tg_token`, `ask_secret`);
any change to how keys are stored or checked.
