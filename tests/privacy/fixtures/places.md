# Privacy places (source for privacy.md)

## t2
when: always
Your company folder stays on your computer and in your own GitHub. Nothing goes to 1610 unless you send it. Connections use each tool's own sign-in, and we never see your passwords.

## your-computer
when: always
Your computer holds the company folder and every area repo you can read; anyone who can open your computer account can read it, and it stays until you delete it.

## team-computers
when: level: team
Each teammate's computer holds a full copy of every repo their account can read; they and anyone who can open their computer account can read it, and the device helper deletes the company folder after the company removes their access.

## ai-vendor
when: always
Each request you or a scheduled job sends to an AI model goes to that model's vendor with the files the request needs; the vendor reads it, keeps it as long as its own rules and your account settings say, and removes it by those same rules.

## vendor-memory
when: always
Your AI apps may keep their own memory, chat history and agent transcripts outside this folder (in the agent's own folder on your computer or in your vendor account); you and the vendor can read them, they stay by the vendor's rules, and you delete them yourself, while the company can only remove your seat at that vendor.

## backups
when: always
Backups you make of your computer (for example Time Machine or a cloud backup) hold a copy of the company folder; anyone who can open the backup can read it, it stays as long as the backup does, and you delete it yourself when you leave.

## hand-copies
when: always
Files you copy out of the folder by hand (downloads, exports, email attachments, pasted text) are copies too; anyone you give them to can read them, they stay until you delete them, and no helper finds them.

## git-host
when: level: team
Your company's own GitHub (or Forgejo) organization holds every company, area and workspace repo with its full history; only the accounts the admin grants can read each repo, the history keeps old versions until the admin rewrites it with `remove-leak`, and a repo goes away only when the admin deletes it.

## workspaces
when: level: team
Each person's workspace repo holds their drafts, profile and working notes; only that person, their own AI and the admin can read it, and when the person leaves the company archives it with admin read only and keeps it unless the admin turns on deletion.

## review-vendor
when: level: team
The review check sends only the pull request under review (its title, body and diff) and `review-rules.md` to the vendor whose key the company added (a second vendor, or your own vendor if you have no second one); that vendor keeps it by its own rules, and you stop it by removing the key.

## outside-parties
when: level: team
Outside parties you grant access to (an advisory firm, a bookkeeper, an agency) hold copies of the repos their accounts can read; they read them under the same rules as staff, and when the work ends they delete those copies and keep only anonymized notes on methods, unless your agreement says otherwise.

## bot-computers
when: switch: bots
Each bot's computer holds a copy of the repos that bot's own account can read; the bot's owner and anyone who can open that computer can read it, and it stays until the owner deletes the bot or its access.

## cloud-agents
when: switch: cloud-handoff
When an agent hands work to a cloud coding agent, that vendor makes a copy of the repo in its cloud; the vendor and the person who started the job can read it, and it stays and is removed by the vendor's rules.

## traces-store
when: level: app and switch: traces
Each person's full AI session history, with secrets removed first, goes to the app's traces store; only that person and the admin can read it, full traces shrink to summaries after 30 days, and the offboarding settings say when they are deleted.

## app-database
when: level: app
The app database and its backups hold records, groups and the log of every connector call; only the people the company's groups allow, plus the named and logged host operators who run the server, can read it, and it stays until the company deletes it or asks for deletion when it leaves.

## connector
when: level: app
The connector server keeps a copy of the repos, a search index and a queue of suggestions not yet reviewed; it shows each person only what their groups allow, and all three are rebuilt from git and deleted with the app.
