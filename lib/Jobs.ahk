StartJob(note, spec) {
    list := []
    for name in spec["connectors"] {
        if SubStr(name, 1, 4) != "new:"
            list.Push(name)
        else if AddConnector(SubStr(name, 5))
            list.Push(SubStr(name, 5))
    }
    spec["connectors"] := list
    topic := EnsureTopic(spec)
    id := FormatTime(, "yyyyMMdd-HHmmss")
    job := Map("id", id, "spec", spec, "note", note, "topic", topic, "round", 1, "status", "starting", "started", A_Now
        , "session", "", "question", "", "deadline", "", "last_input", note, "last_shown", note, "branch", "", "compare", "")
    t := Topics[topic], sid := ""
    if spec["continue"] = "resume" && t.Get("session", "") != "" && DirExist(t.Get("folder", "")) && t.Get("workspace", "") = spec["workspace"] {
        cwd := t["folder"], sid := t["session"], job["branch"] := t.Get("branch", ""), job["compare"] := t.Get("compare", "")
        if SubStr(t.Get("workspace", ""), 1, 8) = "project:"
            OpenInCode(cwd)
    } else {
        if spec["continue"] = "resume"
            spec["continue"] := "memory"
        if (cwd := PrepareWorkspace(job)) = ""
            return
    }
    job["cwd"] := cwd, job["log"] := LogDir "\" id "-" topic ".md"
    header := "# " t["title"] "`n`n"
    if spec["connectors"].Length
        header .= "Connectors: " Join(spec["connectors"], ", ") " (" (spec.Get("connector_access", "read") = "write" ? "changes allowed" : "read-only") ")`n`n"
    FileAppend(header, job["log"], "UTF-8")
    Jobs.Push(job)
    LaunchClaude(job, JobPrompt(job), sid)
    Notify("On it: " t["title"])
}

EnsureTopic(spec) {
    id := spec["topic"]
    if Topics.Has(id)
        return id
    base := RegExReplace(id, "^new:"), id := base, n := 1
    while Topics.Has(id)
        id := base "-" (++n)
    Topics[id] := Map("id", id, "title", spec["topic_title"] != "" ? spec["topic_title"] : base, "summary", ""
        , "session", "", "folder", "", "workspace", spec["workspace"], "last", "", "size", 0)
    spec["topic"] := id
    SaveTopics()
    return id
}

AddConnector(name) {
    if !RegExMatch(name, "^[\w-]+$")
        return false
    if MsgBox('This note asks for a new connector "' name '".`n`nAdd it to connectors.json? It will only be used by Claude-thingy jobs that ask for it. A Claude window will open so you can sign in.', "Claude-thingy", 262212) != "Yes"
        return false
    ib := InputBox("HTTP URL of the " name " MCP server:", "New connector: " name, "w460 h130")
    url := Trim(ib.Value)
    if ib.Result != "OK" || !RegExMatch(url, '^https?://[^\s"&|<>^%]+$')
        return (Notify("No valid URL given, so the " name " connector was skipped.", true), false)
    Connectors[name] := Map("type", "http", "url", url, "description", name " (added from a voice note)")
    FileWriteNew(ConnectorsPath, JsonDump(Connectors, true))
    ConnectorSignIn([name])
    return true
}

ConnectorSignIn(names) {
    path := TempDir "\signin-mcp.json"
    WriteMcpConfig(names, path)
    RunWait(A_ComSpec ' /s /c "echo. & echo Type /mcp, sign in to each server that asks for it, then type /exit. & echo. & "'
        . Cfg["claude"] '" --strict-mcp-config --mcp-config "' path '""', TempDir)
}

PrepareWorkspace(job) {
    ws := job["spec"]["workspace"]
    if RegExMatch(ws, "^project:(.+)$", &m) {
        if !(p := FindProject(m[1])) || !DirExist(p["path"])
            return (Notify("Project folder not found for " m[1] ".", true), "")
        OpenInCode(p["path"])
        return p["path"]
    }
    if RegExMatch(ws, "^clone:([\w.-]+)/([\w.-]+)$", &m)
        return PrepareClone(job, m[1], m[2])
    dir := TempDir "\workspaces\" job["topic"]
    DirCreate(dir)
    return dir
}

PrepareClone(job, owner, repo) {
    t := Topics[job["topic"]], user := Conf("github_user")
    if user = ""
        return (Notify("Set github_user in config.json to use clone: workspaces.", true), "")
    if t.Get("workspace", "") = job["spec"]["workspace"] && t.Get("branch", "") != "" && DirExist(t.Get("folder", "")) {
        job["branch"] := t["branch"], job["compare"] := t["compare"]
        return t["folder"]
    }
    scratch := Conf("scratch_dir", "data\scratch")
    scratch := RegExMatch(scratch, "^(?:[A-Za-z]:|\\\\)") ? scratch : A_ScriptDir "\" scratch
    dir := scratch "\" repo "-" job["id"], branch := Conf("branch_prefix", "claude-thingy/") job["topic"]
    DirCreate(scratch)
    Notify("Cloning " owner "/" repo "...")
    if RunWait('git clone "https://github.com/' owner '/' repo '.git" "' dir '"', , "Hide")
        return (Notify("git clone failed for " owner "/" repo ".", true), "")
    base := RegExReplace(RunCapture("git rev-parse --abbrev-ref origin/HEAD", dir), "^origin/")
    RunWait('git checkout -b "' branch '"', dir, "Hide")
    RunWait('git remote set-url --push origin "PUSH-DISABLED-use-the-fork-remote"', dir, "Hide")
    if user != owner
        RunWait('gh repo fork ' owner '/' repo ' --clone=false --remote=false', dir, "Hide")
    RunWait('git remote add fork "https://github.com/' user '/' repo '.git"', dir, "Hide")
    job["branch"] := branch
    job["compare"] := "https://github.com/" owner "/" repo "/compare/" (base != "" ? base : "main") "..." (user != owner ? user ":" : "") branch "?expand=1"
    return dir
}

OpenInCode(path) => Run(A_ComSpec ' /c code "' path '"', , "Hide")

JobPrompt(job) {
    spec := job["spec"], id := job["topic"], chat := spec["workspace"] = "none"
    rules := Map("question", "Answer the question."
        , "connector", "Use the connected tools (" Join(spec["connectors"], ", ") ") to do the task."
        , "code", chat ? "Put the code in your reply." : "Make the requested change in the working folder and keep it focused."
        , "plan", chat ? "Put the full plan in your reply." : "Write the plan to PLAN.md in the working folder, then stop. Don't make any other changes except the memory file.")
    s := "Topic: " TopicTitle(id) " (id: " id ")`nMemory file: " MemoryPath(id) "`n"
    s .= Map("memory", "Read the memory file first; it holds what you already know about this topic."
        , "resume", "This continues our earlier conversation on this topic."
        , "fresh", "This is a new topic.")[spec["continue"]] "`n"
    s .= "Job: " spec["kind"] ". " rules[spec["kind"]] "`n"
    names := Join(spec["connectors"], ", ")
    if spec["connectors"].Length && spec.Get("connector_access", "read") = "write"
        s .= "You may make the changes the note asks for in " names ".`n"
    else if spec["connectors"].Length
        s .= "You have read-only access to " names ". Don't try to change anything there.`n"
    if chat
        s .= "This is a chat, not a coding session: you have no file or shell tools. Reply with everything in your final message. "
            . "End it with a <memory>...</memory> block holding the full updated memory for this topic (key facts, decisions, links, open questions, under ~300 words), then the optional QUESTION: line.`n"
    else if spec["kind"] = "question" || spec["kind"] = "connector"
        s .= "Don't change local files except the memory file.`n"
    if job["branch"] != ""
        s .= "Git: this folder is a clone of " SubStr(spec["workspace"], 7) " on branch " job["branch"] ". Commit your change, then push ONLY with: git push fork " job["branch"]
            . "`nNever push to origin or any other remote. End your summary with this compare link: " job["compare"] "`n"
    return s "`nNote from " Conf("owner_name", "the user") ":`n" job["note"]
}

AllowedTools(job) {
    spec := job["spec"], list := []
    for name in spec["connectors"] {
        if spec.Get("connector_access", "read") = "write"
            list.Push("mcp__" name "__*")
        else
            for tool in ReadTools(name)
                list.Push("mcp__" name "__" tool)
    }
    if spec["workspace"] = "none" || spec["kind"] = "question" || spec["kind"] = "plan"
        list.Push("WebSearch", "WebFetch")
    if job["branch"] != ""
        list.Push("Bash(git add:*)", "Bash(git commit:*)", "Bash(git status:*)", "Bash(git diff:*)", "Bash(git log:*)"
            , "Bash(git push fork " job["branch"] ":*)", "Bash(git push -u fork " job["branch"] ":*)")
    return list
}

WriteMcpConfig(names, path) {
    servers := Map()
    for name in names
        if Connectors.Has(name) && Connectors[name] is Map {
            def := Connectors[name].Clone()
            for key in ["description", "read_tools"]
                if def.Has(key)
                    def.Delete(key)
            servers[name] := def
        }
    FileWriteNew(path, JsonDump(Map("mcpServers", servers)))
}

WriteBriefing() {
    lines := ["Projects:"]
    for p in Projects
        lines.Push("- " p["name"] ": " p["path"])
    lines.Push("", "Topics (title, last date, memory file):")
    for t in RecentTopics(20)
        lines.Push("- " t["title"] " (" (t.Get("last", "") != "" ? SubStr(t["last"], 1, 10) : "new") "): " MemoryPath(t["id"]))
    template := ReadIf(ConfigDir "\instructions.md")
    template := template != "" ? template : ReadIf(ConfigDir "\instructions.example.md")
    text := StrReplace(StrReplace(template, "{world}", Join(lines, "`n")), "{owner}", Conf("owner_name", "the user"))
    FileWriteNew(BriefingPath, RTrim(text, "`r`n") "`n")
}

LaunchClaude(job, text, sid := "") {
    spec := job["spec"], base := TempDir "\job-" job["id"] "-" job["round"]
    FileWriteNew(base "-prompt.txt", text)
    WriteMcpConfig(spec["connectors"], base "-mcp.json")
    WriteBriefing()
    tools := ""
    for t in AllowedTools(job)
        tools .= ' "' t '"'
    settings := Conf("claude_settings", Map())
    if hasSettings := settings is Map && settings.Count
        FileWriteNew(base "-settings.json", JsonDump(settings))
    chat := spec["workspace"] = "none"
    cmd := '"' Cfg["claude"] '" -p' (sid != "" ? " --resume " sid : "")
        . " --model " spec["model"] " --max-turns " spec["max_turns"] " --output-format json"
        . (chat ? ' --permission-mode dontAsk --tools "Read,Glob,Grep,WebSearch,WebFetch"' : " --permission-mode acceptEdits")
        . (hasSettings ? ' --settings "' base '-settings.json"' : "")
        . ' --strict-mcp-config --mcp-config "' base '-mcp.json" --append-system-prompt-file "' BriefingPath '" --add-dir "' TopicDir '"'
        . (tools != "" ? " --allowedTools" tools : "")
        . ' < "' base '-prompt.txt" > "' base '-out.json" 2> "' base '-err.txt"'
    EnvSet("CLAUDE_CODE_SUBAGENT_MODEL", Conf("subagent_model", "haiku"))
    Run(A_ComSpec ' /s /c "' cmd '"', job["cwd"], "Hide", &pid)
    job["pid"] := pid, job["base"] := base, job["status"] := "running", job["round_started"] := A_Now, job["resumed"] := sid != ""
    SaveJobs(), RebuildJobsMenu()
}

PollJobs() {
    for job in Jobs.Clone() {
        if job["status"] = "running" && !ProcessExist(job["pid"])
            FinishJob(job)
        else if job["status"] = "waiting" && job["deadline"] != "" && A_Now >= job["deadline"]
            AnswerJob(job, "No answer from " Conf("owner_name", "the user") "; continue with your best guess and state your assumptions in the summary.", "(no answer)")
    }
}

FinishJob(job) {
    global LastLog
    raw := ReadIf(job["base"] "-out.json"), err := ReadIf(job["base"] "-err.txt"), spec := job["spec"]
    if job["round"] = 1 && job["resumed"] && InStr(raw err, "No conversation found") {
        spec["continue"] := "memory"
        return LaunchClaude(job, JobPrompt(job))
    }
    res := "", sid := "", failed := true, size := 0, cost := 0
    try {
        r := ParseJsonIn(raw)
        res := r.Get("result", ""), sid := r.Get("session_id", ""), cost := r.Get("total_cost_usd", 0)
        failed := r.Get("is_error", 0) || r.Get("subtype", "") != "success"
        if r.Get("subtype", "") = "error_max_turns"
            res := "I had to stop before finishing this. " res
        steps := r["usage"]["iterations"], last := steps[steps.Length]
        size := last.Get("input_tokens", 0) + last.Get("cache_read_input_tokens", 0) + last.Get("cache_creation_input_tokens", 0) + last.Get("output_tokens", 0)
    }
    res := Trim(res != "" ? res : raw "`n" err, " `t`r`n")
    memory := "", pos := 1
    while RegExMatch(res, "is)<memory>(.*?)</memory>", &mem, pos)
        memory := Trim(mem[1], " `t`r`n"), pos := mem.Pos + mem.Len
    res := Trim(RegExReplace(res, "is)\s*<memory>.*?</memory>\s*", "`n`n"), " `t`r`n")
    if memory != ""
        FileWriteNew(MemoryPath(job["topic"]), memory "`n")
    res := res != "" ? res : "(no output)"
    question := ""
    if !failed {
        lines := StrSplit(res, "`n", "`r")
        if RegExMatch(Trim(lines[lines.Length]), "i)^\**QUESTION:\**\s*(.+)$", &m) {
            question := m[1], lines.Pop()
            res := Trim(Join(lines, "`n") "`n`n" question, " `t`r`n")
        }
    }
    if sid != ""
        job["session"] := sid
    job["status"] := failed ? "failed" : question != "" ? "waiting" : "done"
    job["question"] := question, job["ended"] := A_Now, job["deadline"] := ""
    if question != "" && RegExMatch(spec["ask_policy"], "(\d+)$", &mins)
        job["deadline"] := DateAdd(A_Now, mins[1], "Minutes")
    if Topics.Has(job["topic"]) {
        t := Topics[job["topic"]]
        if sid != ""
            t["session"] := sid
        t["folder"] := job["cwd"], t["workspace"] := spec["workspace"], t["last"] := Iso(), t["size"] := size
        if job["branch"] != ""
            t["branch"] := job["branch"], t["compare"] := job["compare"]
        if !failed
            t["summary"] := FirstLine(res)
        SaveTopics()
    }
    FileAppend("**You:** " job.Get("last_shown", job["last_input"]) "`n`n" res "`n`n---`n`n", job["log"], "UTF-8")
    LastLog := job["log"]
    LogNote(Map("timestamp", Iso(), "transcript", job["last_input"], "spec", spec, "session_id", job["session"], "topic", job["topic"]
        , "status", job["status"], "duration_s", DateDiff(A_Now, job["round_started"], "Seconds"), "cost_usd", cost, "log", job["log"]))
    DeleteJobFiles(job)
    SaveJobs(), RebuildJobsMenu()
    NotifyJob(job, res)
}

StopJob(job) {
    if job["status"] != "running"
        return
    job["status"] := "stopped", job["ended"] := A_Now
    RunWait(A_ComSpec ' /c taskkill /PID ' job["pid"] ' /T /F', , "Hide")
    FileAppend("**You:** " job.Get("last_shown", job["last_input"]) "`n`n_Stopped._`n`n---`n`n", job["log"], "UTF-8")
    LogNote(Map("timestamp", Iso(), "transcript", job["last_input"], "spec", job["spec"], "session_id", job["session"], "topic", job["topic"]
        , "status", "stopped", "duration_s", DateDiff(A_Now, job["round_started"], "Seconds"), "log", job["log"]))
    DeleteJobFiles(job)
    SaveJobs(), RebuildJobsMenu()
    Notify("Stopped: " TopicTitle(job["topic"]))
}

DeleteJobFiles(job) {
    for ext in ["-prompt.txt", "-out.json", "-err.txt", "-mcp.json", "-settings.json"]
        try FileDelete(job["base"] ext)
}

AnswerJob(job, text, shown := "") {
    if job["session"] = "" || !DirExist(job["cwd"])
        return Notify("Can't continue " TopicTitle(job["topic"]) " from here.", true)
    job["round"] += 1, job["last_input"] := text, job["last_shown"] := shown != "" ? shown : text
    job["question"] := "", job["deadline"] := ""
    LaunchClaude(job, text, job["session"])
    Notify("On it: " TopicTitle(job["topic"]))
}

WaitingJobs() {
    list := []
    for job in Jobs
        if job["status"] = "waiting"
            list.Push(job)
    return list
}

LoadJobs() {
    global Jobs := []
    try Jobs := JsonParse(FileRead(JobsPath, "UTF-8"))
    if !(Jobs is Array)
        Jobs := []
}

SaveJobs() {
    while Jobs.Length > 50 && !InList(Jobs[1]["status"], ["running", "waiting"])
        Jobs.RemoveAt(1)
    FileWriteNew(JobsPath, JsonDump(Jobs))
}

RebuildJobsMenu() {
    if !IsObject(JobsMenu)
        return
    JobsMenu.Delete()
    n := 0, shown := 0
    for status in ["running", "waiting"]
        for job in Jobs
            if job["status"] = status
                AddJobItem(job, ++n)
    i := Jobs.Length
    while i >= 1 && shown < 10 {
        if InList(Jobs[i]["status"], ["done", "failed", "stopped"])
            AddJobItem(Jobs[i], ++n), shown++
        i--
    }
    if !n
        JobsMenu.Add("(no jobs yet)", (*) => 0), JobsMenu.Disable("(no jobs yet)")
}

AddJobItem(job, n) => JobsMenu.Add(n ". [" job["status"] "] " SubStr(TopicTitle(job["topic"]), 1, 50), JobClicked.Bind(job))

JobClicked(job, *) {
    if job["status"] = "waiting"
        return ShowReplyGui(job)
    if job["status"] = "running" {
        if MsgBox("Stop working on " TopicTitle(job["topic"]) "?", "Claude-thingy", 262180) = "Yes"
            StopJob(job)
        return
    }
    if FileExist(job.Get("log", ""))
        return OpenFile(job["log"])
    Notify("This job has no log yet.")
}
