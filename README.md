# Claude-thingy

A Windows tool that turns a voice note into a background Claude Code job. Every job behaves like one ongoing assistant that remembers earlier work.

> **Status: alpha (0.x).** It works day to day, but config formats and folders can still change between versions. Read the [changelog](CHANGELOG.md) before updating. [Feedback](#feedback) is very welcome.

1. Press **Ctrl+Alt+Shift+J** (or the `hotkey` you set) to start recording, and press it again to stop. A beep marks the start and the stop. Recording stops on its own at `max_record_seconds`. The audio is transcribed on your machine with whisper.cpp, and the WAV file is deleted.
2. A **dispatcher** turns the note into a job spec: what kind of job it is, where it runs, which connectors and model it uses, how you get notified, and which topic it belongs to. Free keyword rules run first. A single cheap Haiku call fills in anything they don't set, and it's skipped entirely when the rules already decide the kind, workspace and topic (plus the connectors, for connector jobs). The spec records which one routed it in `routed_by` (`rules` or `haiku`).
3. A popup shows the transcript and the spec as editable fields. Fix anything that's wrong, then click **Send**.
4. `claude -p` runs hidden with exactly that setup. When it finishes, you get a notification on the channel you chose, the reply is added to the topic's conversation in `data/topics/<topic>/`, and the topic's memory is updated.

## Dependencies

| Tool | Install |
| --- | --- |
| AutoHotkey v2 | `winget install AutoHotkey.AutoHotkey` |
| ffmpeg | `winget install Gyan.FFmpeg` |
| whisper.cpp | Download `whisper-bin-x64.zip` from https://github.com/ggml-org/whisper.cpp/releases (Windows builds are attached to the `bNNNN` releases). Copy the contents of its `Release` folder into `tools/whisper/`. |
| Whisper model | Download [`ggml-base.en.bin`](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin) into `tools/models/` |
| Claude Code | https://docs.claude.com/en/docs/claude-code (run `claude` once to log in) |
| VS Code | `code` on PATH. Project jobs open the folder in VS Code, which keeps Hackatime tracking. |
| git + GitHub CLI | Only needed for `clone:` jobs. Run `winget install GitHub.cli`, then `gh auth login`. |

## Layout

| Folder | Contents | In git? |
| --- | --- | --- |
| `lib/` | The code | yes |
| `config/` | Your settings, plus `*.example` templates | only the templates |
| `data/` | One folder per topic (conversation and memory), monthly note logs, `clone:` scratch folders. Can be moved, see [Storage](#storage). | no |
| `tools/` | whisper.cpp and the model | no |

## Setup

```powershell
cd config
copy config.example.json config.json
copy projects.example.json projects.json
copy connectors.example.json connectors.json
copy instructions.example.md instructions.md
```

`instructions.md` is the assistant's persona and rules: who it is, how it talks, and what it may mention. It's rebuilt into the briefing before every job. `{owner}` is replaced with `owner_name`, and `{world}` with the list of projects and topics. Keep the memory-file and `QUESTION:` rules, because the app relies on them.

In all JSON files, backslashes in paths must be doubled (`C:\\code\\site`).

### config.json

| Key | Meaning |
| --- | --- |
| `hotkey` | Recording hotkey in AutoHotkey syntax: `^` Ctrl, `!` Alt, `+` Shift, `#` Win. The default is `^!+j` (Ctrl+Alt+Shift+J). Use **Reload** after changing it. |
| `max_record_seconds` | Recording stops on its own after this many seconds (default 180; `0` means no limit). |
| `sounds` | Beeps when recording starts and stops (`true` or `false`). |
| `ffmpeg`, `whisper`, `model`, `mic`, `claude` | Paths to the tools. Leave `mic` empty to use the first microphone ffmpeg finds. |
| `owner_name` | Your name. It replaces `{owner}` in `instructions.md`. |
| `github_user` | Your GitHub username. `clone:` jobs push only to your fork, `github.com/<github_user>/<repo>`. |
| `data_dir` | Where `data/` lives. A relative path is relative to this folder, and the default is `data`. See [Storage](#storage). |
| `scratch_dir` | Where `clone:` jobs clone repos. A relative path is relative to this folder. The default is `data\scratch`. |
| `claude_settings` | Extra Claude Code settings, passed to every job with `--settings`. The default is `{}`. |
| `branch_prefix` | Prefix for the branches `clone:` jobs create. The default is `claude-thingy/`. |
| `subagent_model` | Model for subagents, passed as `CLAUDE_CODE_SUBAGENT_MODEL`. The default is `haiku`. |
| `resume_max_days`, `resume_max_tokens` | A topic resumes its last session only if that session is at most this many days old and its context is at most this many tokens. Otherwise the job starts fresh and reads the memory file. |
| `max_turns` | Turn limit for each kind of job. |
| `notify_default`, `ask_policy_default` | Used when a note doesn't say how to notify you or what to do if Claude has a question. |
| `dry_run` | Set to `true` to start with dry run turned on. |
| `slack.user_id` | Your Slack member ID. In Slack, open your profile, click **⋮** and choose **Copy member ID** (it looks like `U0123ABCD`). |
| `slack.user_token` | Used by `slack-dm:me`. A user token (`xoxp-…`) from a Slack app you create at https://api.slack.com/apps, with the **User Token Scope** `chat:write`. Install the app to your workspace and copy the "User OAuth Token". The DM arrives in your own DM with yourself. |
| `slack.bot_token` | Used by `slack-dm:bot`. A bot token (`xoxb-…`) from the same kind of app, with the **Bot Token Scope** `chat:write`. The message comes from the app's DM. |
| `smtp.*` | Used by `email`. For Gmail, use `smtp.gmail.com`, port `465`, `ssl: true`, your address as `user`/`from`/`to`, and an App Password (https://myaccount.google.com/apppasswords) as `password`. Use port 465 with SSL; STARTTLS on port 587 isn't supported. |

### projects.json

A list of `{ "name": "...", "path": "..." }` entries. The dispatcher picks one when a note mentions it ("…in the site repo", "…README of Claude-thingy").

### connectors.json

This describes the MCP servers a job is allowed to load. The keys are connector names. Each value is a normal MCP server entry (`type`/`url`/`headers` for HTTP servers, or `command`/`args`/`env` for local ones), plus two extra fields that are removed before Claude Code sees the entry:

- `description` tells the dispatcher what the connector is for.
- `read_tools` (optional) lists the exact tool names that only read. With read access (the default), a job may call only these tools; everything else on that server is blocked. With write access, every tool on the server is allowed. A connector with no `read_tools` can only be used with write access, and the popup warns you about it.

The example has Slack, Airtable and GitHub. Check that their URLs are the ones you want. **The `read_tools` names in the example are best guesses and haven't been verified.** To see the real names, open tray → **Sign in to connectors**, type `/mcp`, choose the server and look at its tool list. Correct `read_tools` to match. A read-only job will otherwise be blocked from tools whose names are wrong.

Each job gets a temporary MCP config containing only its chosen connectors (`--mcp-config <file> --strict-mcp-config`), so nothing else loads. Jobs run with `-p`, so they can't do an OAuth sign-in themselves. Do it once from the tray: **Sign in to connectors** opens a visible Claude window with exactly the same config. Type `/mcp`, sign in to each server, then type `/exit`.

If a note needs a service that isn't in the list, the spec gets `new:<name>`. That's never added automatically: when you click **Send**, a dialog asks for confirmation and the server URL. The server is then saved to `connectors.json` only (it's never added to your global Claude Code config, so other sessions don't load it), and the sign-in window opens. The job continues once you close that window. Add `read_tools` for it later if you want read-only jobs to use it.

## Run

Double-click `Claude-thingy.ahk`. Its tray menu has these items:

- **Jobs**: running and waiting jobs, plus the last 10 finished ones. Click a waiting job to answer it, a running job to stop it, or a finished job to open its log.
- **Open last result** and **Open data folder**.
- **Sign in to connectors**: see above.
- **Dry run (route only, start no jobs)**: the popup still shows the spec, but **Send** only logs it to `data/logs/notes-<yyyy-mm>.jsonl`.
- **Reload** and **Exit**.

To start the tool when you log in (optional), press Win+R, type `shell:startup`, and add a shortcut to `Claude-thingy.ahk` in that folder.

## The job spec

| Field | Values |
| --- | --- |
| `kind` | `question` (answer only), `connector` (uses MCP connectors), `code` (changes files), `plan` (writes `PLAN.md` and stops) |
| `workspace` | `project:<name>` runs in that folder and opens VS Code there. `clone:<owner/repo>` makes a fresh clone on a new branch and pushes only to your fork. `none` is a chat: it has only read and web tools (no editing or shell), replies with everything in the message, and runs in its own folder per topic, `%LOCALAPPDATA%\claude-thingy\workspaces\<topic-id>`. |
| `connectors` | Connector names from `connectors.json`, or `new:<name>` |
| `connector_access` | `read` (default): only each connector's `read_tools`. `write`: every tool on the connector, for notes that ask to post, send, reply, create, update, edit, delete or archive something. |
| `routed_by` | `rules` if the free keyword rules decided everything, `haiku` if the dispatcher model was called |
| `notify` | `toast`, `email`, `slack-dm:me`, `slack-dm:bot` |
| `model` | Defaults to `haiku` for question and connector jobs and `sonnet` for code and plan jobs. You get `opus` only if you say "think hard". |
| `max_turns` | From `config.json`, based on the kind |
| `topic` | An existing topic ID, or `new:<slug>` |
| `continue` | `resume` (same session and folder), `memory` (new session that reads the memory file), `fresh` |
| `ask_policy` | `async` (wait for you), or `best-guess-after:<minutes>` |

### Keyword rules (free, and they always win over the dispatcher)

| You say | Sets |
| --- | --- |
| starts with "question" | `kind: question` |
| "plan a…", starts with "plan" | `kind: plan` |
| starts with "fix", or "fix the…" | `kind: code` |
| a connector name ("Airtable", "Slack") | that connector, and `kind: connector` |
| "add the X connector", "new X connector" | `new:X` |
| post, send, reply, message, create, update, edit, add, delete, archive… (not "DM me", "email me" or "send me") | `connector_access: write` (otherwise `read` when a connector is named) |
| "DM me … bot", "with the bot" | `notify: slack-dm:bot` |
| "DM me", "Slack me" | `notify: slack-dm:me` |
| "email me" | `notify: email` |
| "think hard" | `model: opus` |
| "use sonnet" / "with haiku" | that model |
| starts with "continue", "resume", "back to" | `continue: resume` |
| "start fresh", "new topic" | `continue: fresh` and a new topic named after the note, with no model call |
| the title or ID of an existing topic (case and punctuation ignored) | that topic, and its workspace if none is named |
| "best guess after 10 minutes", "don't ask me" | `ask_policy: best-guess-after:…` |
| "…in/of/for <project>", "<project> repo" | `workspace: project:<project>` |
| a github.com URL, "fork of owner/repo" | `workspace: clone:owner/repo` |
| a question or connector job that names no project | `workspace: none` |

### Changing the spec in the popup

Every field is a dropdown or text box. If you change the kind and haven't touched the model, the model switches to that kind's default. Choosing a topic updates the "Continuing: <topic>, <n> days ago" line and suggests a continue mode. You can also type a topic: an existing topic's ID or title picks that topic, and anything else starts a new topic with what you typed as its title. **Access** switches connectors between `read` and `write`. A red line warns when a read-only connector has no `read_tools`.

### Testing routing without the popup

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" route-test.ahk "Question: what's a fork?" "Fix the typo in the README of Claude-thingy." > route.txt
```

This prints the spec for each note. It only runs the dispatcher and never starts a job.

## One assistant: briefing, topics and memory

- Before every job, `data/topics/briefing.md` is built from `instructions.md` plus a world index (projects plus your most recent topics with their memory files) and passed with `--append-system-prompt-file`. Its wording stays the same between jobs so prompt caching works well.
- `data/topics/<id>/memory.md` is each topic's memory. Project and clone jobs edit it directly. Chat jobs (`none`) have no file tools, so they end their reply with a `<memory>…</memory>` block. The app saves that block to the memory file and removes it from the reply before logging and notifying. If the block is missing, the old memory stays. Jobs can read `data/topics/` through `--add-dir`.
- `data/topics/<id>/conversation.md` is the whole conversation on that topic: every note or answer and every reply, in order.
- `data/topics/index.json` stores each topic's ID, title, one-line summary, last session ID, working folder, last date and approximate context size.

## Questions and answers

If a reply ends with a `QUESTION: …` line, the job becomes **waiting** and you're notified on the job's channel. Nothing steals focus. You can answer in three ways:

- Click the notification, or the job under tray → **Jobs**. A small reply window opens without taking focus.
- Record a voice note that starts with **"answer"**. It goes to the waiting job, and if several are waiting, a picker appears.
- With `best-guess-after:<minutes>`, the job resumes on its own after that many minutes and states its assumptions.

An answer resumes the same session (`--resume <id>`) from the same folder with the same settings.

## Logs

- **Jobs** and **Open last result** open the topic's `conversation.md`.
- `data/logs/notes-<yyyy-mm>.jsonl` (one file per month) has one line per run with the transcript, the spec, session ID, topic, status, duration, cost and log path. It also records dry runs and cancelled notes.
- `data/logs/jobs.json` stores job state, so running and waiting jobs survive a **Reload**.

## Safety

- No job uses `--dangerously-skip-permissions`.
- Project and clone jobs use `--permission-mode acceptEdits`. Shell commands are refused unless they're explicitly allowed. The only ones allowed are, for `clone:` jobs, `git add/commit/status/diff/log` and `git push fork <job-branch>`.
- Chat jobs (`none`) use `--permission-mode dontAsk` with `--tools "Read,Glob,Grep,WebSearch,WebFetch"`, so they can't edit files or run commands. Anything not pre-approved is denied.
- In `clone:` folders, the push URL of `origin` is set to an invalid value, so pushing to the upstream repo fails even if something tries it.
- Only the connectors in the spec are loaded. With read access, only `mcp__<name>__<tool>` for each of its `read_tools` is allowed. With write access, `mcp__<name>__*` is allowed. Chat, question and plan jobs may also use web search and fetch.
- User plugins aren't disabled, so the WakaTime plugin keeps working.

## Storage

Everything Claude-thingy writes is small text: about 4 KB per job, so a thousand jobs come to around 4 MB. All saves go to a temporary file first and then replace the real file, so a crash can't leave a half-written file behind.

To keep this data off your laptop, put it in a cloud-synced folder:

1. Quit Claude-thingy and move the `data` folder into, for example, OneDrive (`C:\Users\<you>\OneDrive\Claude-thingy-data`).
2. Set `data_dir` in `config.json` to that path, then start Claude-thingy.
3. Optional: in File Explorer, right-click the folder and choose **Free up space**. OneDrive then keeps only placeholders on your disk and downloads a file when it's opened.

Other places things are stored:

- `tools/` (about 170 MB) holds whisper.cpp and its model. Its size is fixed.
- `clone:` jobs keep a full clone in `data\scratch` per topic. These are the only folders that can get big. Delete old ones once their branch is pushed.
- Chat folders in `%LOCALAPPDATA%\claude-thingy\workspaces` stay empty. They only exist so a topic can be resumed from the same folder. Unlike `%TEMP%`, Windows doesn't clean them up automatically.
- Claude Code keeps its own session history in its user folder. Claude-thingy doesn't manage that.

## Hackatime

Every job is tracked; nothing is excluded. User plugins stay on, so the WakaTime plugin runs for every job. The project name comes from the folder a job runs in:

| Job | Runs in | Shows up on Hackatime as |
| --- | --- | --- |
| `project:<name>` | the project folder (VS Code opens there too) | the project's folder name, e.g. `site` |
| `clone:<owner/repo>` | `data\scratch\<repo>-<job-id>` | that clone folder's name, e.g. `site-20261031-101500` |
| `none` (chat) | `%LOCALAPPDATA%\claude-thingy\workspaces\<topic-id>` | the topic ID, e.g. `merge-vs-rebase` |
| the dispatcher's Haiku call (and `route-test.ahk`) | `%TEMP%\claude-thingy` | `claude-thingy` |

## TODO

- Accept answers to waiting jobs as replies in a Slack thread. This isn't in this version: answers come only from the reply window, an "answer" voice note, or best-guess.
- Let code jobs run an allowlist of build and test commands in project workspaces.

## Troubleshooting

- **The spec is wrong**: fix it in the popup. To experiment cheaply, turn on **Dry run** or use `route-test.ahk`.
- **"Dispatcher failed … safe defaults"**: the Haiku call didn't return valid JSON. Check that `claude -p "hi"` works in a terminal.
- **A connector job can't see its tools**: run tray → **Sign in to connectors** and sign in to that server.
- **A read-only connector job says a tool was blocked**: that tool isn't in the connector's `read_tools`, or the name there is wrong. Check the real names with `/mcp` in the sign-in window, or switch **Access** to `write` for that job.
- **Slack or email didn't arrive**: you'll get a toast instead, saying why (missing token, Slack API error, SMTP error).
- **A resume failed**: if the old session no longer exists, the job restarts automatically using the memory file.
- **Mic or transcription problems**: see v1. List devices with `ffmpeg -hide_banner -list_devices true -f dshow -i dummy` and set `mic` in `config.json`.
- **Check the scripts for errors**: `AutoHotkey64.exe /ErrorStdOut /validate Claude-thingy.ahk`

## Updating

Download the latest release from [Releases](../../releases), or run `git pull`. Your own files (`config/*.json`, `config/instructions.md`, `data/` and `tools/`) aren't part of the release, so they stay as they are. Check the [changelog](CHANGELOG.md) for anything marked **Changed**, which tells you if a config file needs editing. Then use tray → **Reload**. The tray tooltip shows which version you're running.

## Feedback

This is an early release, and feedback shapes what comes next.

- **Something broke?** [Open a bug report](../../issues/new/choose). It asks for your version (hover over the tray icon) and what happened. Remove tokens and anything private before pasting.
- **Have an idea, or something felt clunky?** [Suggest a feature](../../issues/new/choose). The problem you ran into matters more than the solution.

## License

MIT. See [LICENSE](LICENSE).
