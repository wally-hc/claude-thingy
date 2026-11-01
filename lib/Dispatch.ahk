Route(note) {
    global RouteError := ""
    rules := RuleSpec(note)
    llm := Map()
    useModel := !rules.Has("kind") || !rules.Has("workspace") || !rules.Has("topic") || (rules["kind"] = "connector" && !rules.Has("connectors"))
    if useModel
        llm := AskDispatcher(note)
    if rules.Has("notify") && llm.Has("connectors") && llm["connectors"] is Array {
        kept := []
        for c in llm["connectors"]
            if IsObject(c) || !RegExMatch(c, "i)^(?:new:)?(?:e-?mail|mail|gmail|smtp|slack|toast)$")
                kept.Push(c)
        llm["connectors"] := kept
    }
    s := Map("kind", "question", "workspace", "none", "connectors", [], "connector_access", "read", "topic", "", "topic_title", ""
        , "notify", Conf("notify_default", "toast"), "ask_policy", Conf("ask_policy_default", "async"), "routed_by", useModel ? "haiku" : "rules")
    for src in [llm, rules]
        for k, v in src
            s[k] := v
    s := ValidSpec(s, note)
    if !rules.Has("model")
        s["model"] := DefaultModel(s["kind"])
    s["max_turns"] := DefaultTurns(s["kind"])
    if rules.Get("continue", "") = "session" && s["workspace"] != "none"
        s["continue"] := "session"
    else
        s["continue"] := rules.Get("continue", "") = "fresh" ? "fresh" : SuggestContinue(s["topic"])
    if s["continue"] = "resume" && Topics[s["topic"]].Get("workspace", "") != s["workspace"]
        s["continue"] := "memory"
    return s
}

RuleSpec(note) {
    s := Map(), t := StrLower(note)
    lead := RegExReplace(t, "^\W*(?:(?:start fresh|from scratch|new topic|continue|resume)\b\W*)+")
    if RegExMatch(lead, "^\W*(?:quick\s+)?question\b")
        s["kind"] := "question"
    else if RegExMatch(lead, "^\W*(?:think (?:really )?hard\W+(?:and\W+)?)?(?:make |write |draft )?(?:a |the )?plan\b|\bplan (?:out )?(?:a|an|the|my)\b")
        s["kind"] := "plan"
    else if RegExMatch(lead, "^\W*(?:please\s+)?(?:fix|implement|refactor|patch)\b|\bfix (?:the|a|this)\b")
        s["kind"] := "code"

    if RegExMatch(t, "\b(?:dm|message|ping|slack) me\b[^.;!?]*?\bbot\b|\b(?:with|via|from|using) the (?:slack )?bot\b")
        s["notify"] := "slack-dm:bot"
    else if RegExMatch(t, "\b(?:dm|slack|ping) me\b|\bmessage me on slack\b")
        s["notify"] := "slack-dm:me"
    else if RegExMatch(t, "\b(?:e-?mail|mail) me\b|\bsend me an? e-?mail\b")
        s["notify"] := "email"
    else if RegExMatch(t, "\b(?:toast|just notify me)\b")
        s["notify"] := "toast"
    rest := RegExReplace(t, "\b(?:dm|message|ping|slack|e-?mail|mail) me\b[^.;!?]*")

    if RegExMatch(t, "\bthink (?:really )?hard\b|\bultrathink\b")
        s["model"] := "opus"
    else if RegExMatch(t, "\b(?:use|with|on) (haiku|sonnet|opus)\b", &m)
        s["model"] := m[1]

    if RegExMatch(t, "^\W*(?:continue|resume|pick up|back to)\b")
        s["continue"] := "resume"
    if RegExMatch(t, "\b(?:where i left off|my (?:last|latest|current) session|from my session|continue my session)\b")
        s["continue"] := "session"
    if RegExMatch(t, "\b(?:start fresh|from scratch|new topic)\b") {
        s["continue"] := "fresh"
        rest2 := Trim(RegExReplace(note, "i)\b(?:start fresh|from scratch|new topic)\b\W*"), " `t.,:;")
        rest2 := Trim(RegExReplace(rest2, "i)^(?:quick\s+)?question\b\W*"), " `t.,:;")
        title := Trim(RegExReplace(rest2, "[.,;:!?].*$"))
        s["topic"] := "new:" Slug(title != "" ? title : rest2)
        s["topic_title"] := StrUpper(SubStr(title, 1, 1)) SubStr(title, 2)
    } else if (id := TopicInNote(note)) != ""
        s["topic"] := id

    if RegExMatch(t, "\bbest guess after (\d+) ?min", &m)
        s["ask_policy"] := "best-guess-after:" m[1]
    else if RegExMatch(t, "\b(?:don'?t ask me|just guess|use your best guess)\b")
        s["ask_policy"] := "best-guess-after:0"

    if RegExMatch(note, "i)github\.com/([\w.-]+/[\w-]+(?:\.[\w-]+)*?)(?:\.git)?(?![\w.-])", &m)
        || RegExMatch(note, "i)\b(?:clone|fork)(?: of)? ([\w.-]+/[\w.-]+)", &m)
        s["workspace"] := "clone:" m[1]
    else if RegExMatch(t, "\bno (?:project|workspace)\b")
        s["workspace"] := "none"
    else {
        for p in Projects {
            n := RegExReplace(StrLower(p["name"]), "[^a-z0-9]", "[-\s.]?")
            if RegExMatch(t, "\b(?:in|of|on|for|to|at|from) (?:the )?" n "(?![\w-])|(?<![\w-])" n " (?:project|repo|folder)\b") {
                s["workspace"] := "project:" p["name"]
                break
            }
        }
    }

    found := []
    for name in Connectors
        if RegExMatch(rest, "(?<![\w-])" RegExReplace(StrLower(name), "[^a-z0-9]", "[-\s.]?") "(?![\w-])")
            found.Push(name)
    if RegExMatch(rest, "\b(?:new|add(?: the| a)?) ([\w-]+) connector\b", &m) && !Connectors.Has(m[1])
        found.Push("new:" m[1])
    if found.Length {
        s["connectors"] := found
        if !s.Has("kind")
            s["kind"] := "connector"
    }
    changes := RegExMatch(rest, "\b(?:post|send|reply|respond|message|create|update|edit|delete|remove|archive|add|write|comment|react|assign|invite|schedule|mark|move|rename)\b(?!\s+me\b)")
    if changes || found.Length
        s["connector_access"] := changes ? "write" : "read"
    if !s.Has("workspace") && s.Has("topic") && Topics.Has(s["topic"]) && Topics[s["topic"]].Get("workspace", "") != ""
        s["workspace"] := Topics[s["topic"]]["workspace"]
    if !s.Has("workspace") && InList(s.Get("kind", ""), ["question", "connector"])
        s["workspace"] := "none"
    return s
}

TopicInNote(note) {
    text := " " NormWords(note) " ", best := "", bestLen := 0
    for id, t in Topics
        for name in [t["title"], id]
            if (n := NormWords(name)) != "" && InStr(text, " " n " ") && StrLen(n) > bestLen
                best := id, bestLen := StrLen(n)
    return best
}

TopicByName(text) {
    n := NormWords(text)
    for id, t in Topics
        if n != "" && (n = NormWords(t["title"]) || n = NormWords(id))
            return id
    return ""
}

NormWords(text) => Trim(RegExReplace(StrLower(text), "[^a-z0-9]+", " "))

AskDispatcher(note) {
    global RouteError
    base := TempDir "\dispatch"
    FileWriteNew(base "-system.txt", DispatcherSystem())
    FileWriteNew(base "-input.txt", DispatcherInput(note))
    FileWriteNew(base "-mcp.json", '{"mcpServers":{}}')
    try FileDelete(base "-out.json")
    RunWait(A_ComSpec ' /s /c ""' Cfg["claude"] '" -p --model haiku --tools "" --max-turns 1 --output-format json'
        . ' --strict-mcp-config --mcp-config "' base '-mcp.json" --system-prompt-file "' base '-system.txt"'
        . ' < "' base '-input.txt" > "' base '-out.json" 2>&1"', TempDir, "Hide")
    picked := Map()
    try {
        spec := ParseJsonIn(ParseJsonIn(ReadIf(base "-out.json"))["result"])
        for k in ["kind", "workspace", "connectors", "connector_access", "topic", "topic_title"]
            if spec.Has(k)
                picked[k] := spec[k]
    } catch as e
        RouteError := "Dispatcher failed (" e.Message "), so safe defaults were used."
    return picked
}

DispatcherSystem() {
    return Join([
        "You route one voice note to one background Claude Code job.",
        "Reply with ONLY one JSON object, no prose and no code fences, shaped like:",
        '{"kind":"question","workspace":"none","connectors":[],"connector_access":"read","topic":"new:short-slug","topic_title":"Short title"}',
        "Fields:",
        "- kind: question (answer or explain; no files change), connector (needs an external service from the connector list), code (change files in a project or GitHub repo), plan (design or plan something; the output is only a written plan).",
        "- workspace: project:<name> when the note is about one of the projects (match names loosely; spoken names may lose dashes); clone:<owner/repo> only for a GitHub repo that is not a project; otherwise none.",
        "- connectors: names from the connector list that the job needs, or []. Use new:<name> only when the job needs a service that is not in the list. Asking to be notified (DM me, email me) is not a connector.",
        "- connector_access: write only when the note asks to change something in a connected service (post, send, reply, create, update, edit, delete, archive); otherwise read. Asking to be notified is not a change.",
        "- topic: the id of an existing topic when the note continues or clearly relates to it; otherwise new:<short-kebab-slug>.",
        "- topic_title: a short human title for the topic."
    ], "`n")
}

DispatcherInput(note) {
    s := "Projects:`n"
    for p in Projects
        s .= "- " p["name"] "`n"
    s .= "`nConnectors:`n"
    for name, d in Connectors
        s .= "- " name ": " (d is Map ? d.Get("description", "") : "") "`n"
    s .= "`nTopics:`n"
    for t in RecentTopics(30)
        s .= "- " t["id"] ": " t["title"] ". " t.Get("summary", "") " (last " SubStr(t.Get("last", ""), 1, 10) ")`n"
    return s "`nNote:`n" note
}

ValidSpec(s, note) {
    kind := StrLower(GetStr(s, "kind"))
    s["kind"] := InList(kind, Kinds) ? kind : "question"
    model := StrLower(GetStr(s, "model"))
    s["model"] := InList(model, Models) ? model : DefaultModel(s["kind"])
    notifier := StrLower(GetStr(s, "notify"))
    s["notify"] := InList(notifier, Notifiers) ? notifier : "toast"
    s["workspace"] := ValidWorkspace(GetStr(s, "workspace"))
    list := []
    if s.Has("connectors") && s["connectors"] is Array
        for c in s["connectors"] {
            name := IsObject(c) ? "" : ConnectorName(c)
            if name != "" && !InList(name, list)
                list.Push(name)
        }
    s["connectors"] := list
    s["connector_access"] := list.Length && StrLower(GetStr(s, "connector_access")) = "write" ? "write" : "read"
    s["routed_by"] := GetStr(s, "routed_by")
    s["topic_title"] := GetStr(s, "topic_title")
    typed := GetStr(s, "topic"), topic := StrLower(typed)
    if topic = ""
        topic := "new:" Slug(note)
    else if !Topics.Has(topic) && (id := TopicByName(typed)) != ""
        topic := id
    else if !Topics.Has(topic) && !RegExMatch(topic, "^new:[a-z0-9][a-z0-9-]*$")
        typed := RegExReplace(typed, "i)^new:\s*"), topic := "new:" Slug(typed), s["topic_title"] := typed
    s["topic"] := topic
    ask := StrLower(GetStr(s, "ask_policy"))
    s["ask_policy"] := RegExMatch(ask, "^(async|best-guess-after:\d+)$") ? ask : "async"
    cont := GetStr(s, "continue")
    if RegExMatch(cont, "i)^session(?::([\w.-]+))?$", &sm) {
        if s["workspace"] = "none" || (sm[1] = "" && SubStr(s["workspace"], 1, 8) != "project:")
            cont := Topics.Has(topic) ? SuggestContinue(topic) : "fresh"
        else
            cont := "session" (sm[1] != "" ? ":" sm[1] : "")
    } else {
        cont := StrLower(cont)
        if !Topics.Has(topic)
            cont := "fresh"
        else if !InList(cont, ContinueModes) || (cont = "resume" && Topics[topic].Get("session", "") = "")
            cont := SuggestContinue(topic)
    }
    s["continue"] := cont
    turns := s.Get("max_turns", "")
    s["max_turns"] := IsInteger(turns) && turns > 0 ? Integer(turns) : DefaultTurns(s["kind"])
    return s
}

GetStr(m, key) => m.Has(key) && !IsObject(m[key]) ? Trim(String(m[key])) : ""

ValidWorkspace(ws) {
    if RegExMatch(ws, "i)^project:(.+)$", &m) && (p := FindProject(m[1]))
        return "project:" p["name"]
    if RegExMatch(ws, "^clone:[\w.-]+/[\w.-]+$")
        return ws
    return "none"
}

FindProject(name) {
    for p in Projects
        if p["name"] = name
            return p
    return ""
}

ConnectorName(name) {
    if RegExMatch(name, "i)^new:([\w-]+)$", &m)
        return ConnectorName(m[1]) != "" ? ConnectorName(m[1]) : "new:" StrLower(m[1])
    for key in Connectors
        if key = name
            return key
    return ""
}

SuggestContinue(topic) => !Topics.Has(topic) ? "fresh" : CanResume(Topics[topic]) ? "resume" : "memory"
DefaultModel(kind) => kind = "code" || kind = "plan" ? "sonnet" : "haiku"
DefaultTurns(kind) => Conf("max_turns." kind, Map("question", 10, "connector", 20, "code", 40, "plan", 25).Get(kind, 10))

InfoLine(topic) {
    if !Topics.Has(topic)
        line := "New topic: " RegExReplace(topic, "^new:")
    else {
        days := DaysAgo(Topics[topic].Get("last", ""))
        line := "Continuing: " Topics[topic]["title"] ", " (days >= 9999 ? "not run yet" : days " day" (days = 1 ? "" : "s") " ago")
    }
    return RouteError != "" ? line "   (" RouteError ")" : line
}

SpecWarning(names, access, cont, ws := "") {
    text := AccessWarning(names, access)
    if cont = "session"
        text .= (text != "" ? "`n" : "") SessionInfo(ws)
    else if SubStr(cont, 1, 8) = "session:"
        text .= (text != "" ? "`n" : "") "This loads that whole conversation, so long sessions cost more."
    return text
}

SessionInfo(ws) {
    if !RegExMatch(ws, "^project:(.+)$", &m) || !(p := FindProject(m[1]))
        return "Continuing your latest session only works for a project."
    s := LatestSession(p["path"])
    if !IsObject(s)
        return "There's no Claude Code session in " p["name"] " to continue."
    when := FormatTime(s.time, "MMM d, HH:mm")
    if s.kb > Conf("session_max_mb", 2) * 1024
        return "Your latest session in " p["name"] " (" when ") is " s.kb " KB, over the session_max_mb limit, so it won't start."
    return "Continues your latest session in " p["name"] " (last used " when ", " s.kb " KB). Bigger sessions cost more."
}

AccessWarning(names, access) {
    lines := []
    if access != "write"
        for name in names
            if Connectors.Has(name) && ReadTools(name).Length = 0
                lines.Push(name " has no read_tools, so its tools will be blocked; switch to write or add read_tools")
    return Join(lines, "`n")
}

ReadTools(name) {
    def := Connectors.Has(name) ? Connectors[name] : ""
    return def is Map && def.Has("read_tools") && def["read_tools"] is Array ? def["read_tools"] : []
}
