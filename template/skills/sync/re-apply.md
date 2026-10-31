# Re-apply a change

A file was changed here and on the host before either side merged. Git does not merge it by machine. Sync kept the person's version aside, put the host's text in the folder, and held the file with `re-apply: changed on the host while you worked`. You merge it by intent: you still know what the person wanted, and you have all three texts. Delete on one side and edit on the other is the same case.

## When

At session start, when `sync.sh status` lists a `re-apply:` hold. Before other work on that file.

## Steps

1. Run `skills/sync/sync.sh re-apply`. For each file it prints:
   - `now:` the host's text, in the folder (or `deleted on the host`);
   - `base:` the text the person's change started from (or `none (a new file)`);
   - `mine:` the person's version (or `deleted here`);
   - `asked:` the question already sent, if any. Skip that file: it waits for the person.
2. Read `base` and `mine`. Write down the person's change in one or two lines: what they added, removed or reworded. Read `now` and work out what the host changed since `base`.
3. Decide:
   - **The change still makes sense on `now`.** Make that change in the folder file, on top of `now`. Do not copy `mine` over it: that would undo the other person's work. Then run `skills/sync/sync.sh re-apply done <repo> <path>`. The next push sends it.
   - **The change is already in `now`.** Run `re-apply done`. Nothing else.
   - **The two changes disagree.** Examples: the person added a line someone else has since removed; one side deleted the file and the other edited it; both rewrote the same sentence two ways. Do not decide. Leave the folder file as the host has it.
4. A disagreement goes to a person:
   - If the person is in this chat: tell them in one line what each side did, and ask which to keep. Do what they say, then run `re-apply done`.
   - Otherwise (a scheduled run, or they are away): run `skills/sync/sync.sh re-apply ask <repo> <path> "<one line: what each side did>"`. It writes the line to the person's inbox (`users/<person>/inbox/re-apply.md`), comments on this computer's open sync pull request for that repo, and lists the question in the nightly digest. The hold stays until the person answers.

## Rules

- Never write conflict markers. Never merge two versions line by line.
- Never put a set-aside copy back over the folder file.
- Never edit `base` or `mine`. `re-apply done` deletes them.
- One file at a time. `<repo>` is as printed: `root`, `area:<name>` or `workspace`.
