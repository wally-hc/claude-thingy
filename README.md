# Claude-thingy

A Windows tool that turns a voice note into a background Claude Code job. Every job behaves like one ongoing assistant that remembers earlier work.

1. Press **Ctrl+Alt+Shift+J** (or the `hotkey` you set) to start recording, and press it again to stop. A beep marks the start and the stop. Recording stops on its own at `max_record_seconds`. The audio is transcribed on your machine with whisper.cpp, and the WAV file is deleted.
2. A **dispatcher** turns the note into a job spec: what kind of job it is, where it runs, which connectors and model it uses, how you get notified, and which topic it belongs to. Free keyword rules run first. A single cheap Haiku call fills in anything they don't set.
3. A popup shows the transcript and the spec as editable fields. Fix anything that's wrong, then click **Send**.
4. `claude -p` runs hidden with exactly that setup. When it finishes, you get a notification on the channel you chose, the result is saved to `data/logs/`, and the topic's memory file is updated.

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
| `data/` | Logs, topics and memory, `clone:` scratch folders | no |
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

This describes the MCP servers a job is allowed to load. The keys are connector names. Each value is a normal MCP server entry (`type`/`url`/`headers` for HTTP servers, or `command`/`args`/`env` for local ones) plus a `description` that tells the dispatcher what the connector is for. The example has Slack, Airtable and GitHub. Check that their URLs are the ones you want.

Each job gets a temporary MCP config containing only its chosen connectors (`--mcp-config <file> --strict-mcp-config`), so nothing else loads. Jobs run with `-p`, so they can't do an OAuth sign-in themselves. Do it once from the tray: **Sign in to connectors** opens a visible Claude window with exactly the same config. Type `/mcp`, sign in to each server, then type `/exit`.

If a note needs a service that isn't in the list, the spec gets `new:<name>`. That's never added automatically: when you click **Send**, a dialog asks for confirmation and the server URL. It then runs `claude mcp add` in a visible window, adds the server to `connectors.json`, and opens the sign-in window. The job continues once you close that window.

## Run

Double-click `Claude-thingy.ahk`. Its tray menu has these items:

- **Jobs**: running and waiting jobs, plus the last 10 finished ones. Click a waiting job to answer it, a running job to stop it, or a finished job to open its log.
- **Open last result** and **Open logs folder**.
- **Sign in to connectors**: see above.
- **Dry run (route only, start no jobs)**: the popup still shows the spec, but **Send** only logs it to `data/logs/notes.jsonl`.
- **Reload** and **Exit**.

To start the tool when you log in (optional), press Win+R, type `shell:startup`, and add a shortcut to `Claude-thingy.ahk` in that folder.

## The job spec

| Field | Values |
| --- | --- |
| `kind` | `question` (answer only), `connector` (uses MCP connectors), `code` (changes files), `plan` (writes `PLAN.md` and stops) |
| `workspace` | `project:<name>` runs in that folder and opens VS Code there. `clone:<owner/repo>` makes a fresh clone on a new branch and pushes only to your fork. `none` replies like a chat and leaves no files; it runs in an empty temp folder. |
| `connectors` | Connector names from `connectors.json`, or `new:<name>` |
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
| "DM me … bot", "with the bot" | `notify: slack-dm:bot` |
| "DM me", "Slack me" | `notify: slack-dm:me` |
| "email me" | `notify: email` |
| "think hard" | `model: opus` |
| "use sonnet" / "with haiku" | that model |
| starts with "continue", "resume", "back to" | `continue: resume` |
| "start fresh", "new topic" | `continue: fresh` |
| "best guess after 10 minutes", "don't ask me" | `ask_policy: best-guess-after:…` |
| "…in/of/for <project>", "<project> repo" | `workspace: project:<project>` |
| a github.com URL, "fork of owner/repo" | `workspace: clone:owner/repo` |

### Changing the spec in the popup

Every field is a dropdown or text box. If you change the kind and haven't touched the model, the model switches to that kind's default. Choosing a topic updates the "Continuing: <topic>, <n> days ago" line and suggests a continue mode.

### Testing routing without the popup

```powershell
& "$env:LOCALAPPDATA\Programs\AutoHotkey\v2\AutoHotkey64.exe" route-test.ahk "Question: what's a fork?" "Fix the typo in the README of Claude-thingy." > route.txt
```

This prints the spec for each note. It only runs the dispatcher and never starts a job.

## One assistant: briefing, topics and memory

- Before every job, `data/topics/briefing.md` is built from `instructions.md` plus a world index (projects plus your most recent topics with their memory files) and passed with `--append-system-prompt-file`. Its wording stays the same between jobs so prompt caching works well.
- `data/topics/<id>.md` is each topic's memory, written by Claude. Jobs get access to the `data/topics/` folder through `--add-dir`.
- `data/topics/index.json` stores each topic's ID, title, one-line summary, last session ID, working folder, last date and approximate context size.

## Questions and answers

If a reply ends with a `QUESTION: …` line, the job becomes **waiting** and you're notified on the job's channel. Nothing steals focus. You can answer in three ways:

- Click the notification, or the job under tray → **Jobs**. A small reply window opens without taking focus.
- Record a voice note that starts with **"answer"**. It goes to the waiting job, and if several are waiting, a picker appears.
- With `best-guess-after:<minutes>`, the job resumes on its own after that many minutes and states its assumptions.

An answer resumes the same session (`--resume <id>`) from the same folder with the same settings.

## Logs

- `data/logs/<job-id>-<topic>.md` is the conversation: each note or answer and each reply. This is what **Jobs** and **Open last result** open.
- `data/logs/notes.jsonl` has one line per run with the transcript, the spec, session ID, topic, status, duration, cost and log path. It also records dry runs and cancelled notes.
- `data/logs/jobs.json` stores job state, so running and waiting jobs survive a **Reload**.

## Safety

- Jobs use `--permission-mode acceptEdits` and never `--dangerously-skip-permissions`. Shell commands are refused unless they're explicitly allowed. The only ones allowed are, for `clone:` jobs, `git add/commit/status/diff/log` and `git push fork <job-branch>`.
- In `clone:` folders, the push URL of `origin` is set to an invalid value, so pushing to the upstream repo fails even if something tries it.
- Connector tools (`mcp__<name>`) are allowed only for the connectors in the spec. Question and plan jobs may also use web search and fetch.
- User plugins aren't disabled, so the WakaTime plugin keeps working.

## Hackatime

- Project jobs run in the project folder and open VS Code there, so their time is logged under the project's name.
- `none` jobs run in `%TEMP%\claude-thingy\workspaces\<topic>`, so they show up under the topic ID.
- `clone:` jobs show up under the clone folder's name.
- The dispatcher's Haiku call runs in `%TEMP%\claude-thingy` and counts under "claude-thingy".

## TODO

- Accept answers to waiting jobs as replies in a Slack thread. This isn't in this version: answers come only from the reply window, an "answer" voice note, or best-guess.
- Let code jobs run an allowlist of build and test commands in project workspaces.

## Troubleshooting

- **The spec is wrong**: fix it in the popup. To experiment cheaply, turn on **Dry run** or use `route-test.ahk`.
- **"Dispatcher failed … safe defaults"**: the Haiku call didn't return valid JSON. Check that `claude -p "hi"` works in a terminal.
- **A connector job can't see its tools**: run tray → **Sign in to connectors** and sign in to that server.
- **Slack or email didn't arrive**: you'll get a toast instead, saying why (missing token, Slack API error, SMTP error).
- **A resume failed**: if the old session no longer exists, the job restarts automatically using the memory file.
- **Mic or transcription problems**: see v1. List devices with `ffmpeg -hide_banner -list_devices true -f dshow -i dummy` and set `mic` in `config.json`.
- **Check the scripts for errors**: `AutoHotkey64.exe /ErrorStdOut /validate Claude-thingy.ahk`

## License

MIT. See [LICENSE](LICENSE).
