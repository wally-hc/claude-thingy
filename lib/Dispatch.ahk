Route(note) {
    global RouteError := ""
    rules := RuleSpec(note)
    llm := Map()
    if !rules.Has("kind") || !rules.Has("workspace") || !rules.Has("topic") || (rules["kind"] = "connector" && !rules.Has("connectors"))
        llm := AskDispatcher(note)
    if rules.Has("notify") && llm.Has("connectors") && llm["connectors"] is Array {
        kept := []
        for c in llm["connectors"]
            if IsObject(c) || !RegExMatch(c, "i)^(?:new:)?(?:e-?mail|mail|gmail|smtp|slack|toast)$")
                kept.Push(c)
        llm["connectors"] := kept
    }
    s := Map("kind", "question", "workspace", "none", "connectors", [], "topic", "", "topic_title", ""
        , "notify", Conf("notify_default", "toast"), "ask_policy", Conf("ask_policy_default", "async"))
    for src in [llm, rules]
        for k, v in src
            s[k] := v
    s := ValidSpec(s, note)
    if !rules.Has("model")
        s["model"] := DefaultModel(s["kind"])
    s["max_turns"] := DefaultTurns(s["kind"])
    s["continue"] := rules.Get("continue", "") = "fresh" ? "fresh" : SuggestContinue(s["topic"])
    if s["continue"] = "resume" && Topics[s["topic"]].Get("workspace", "") != s["workspace"]
        s["continue"] := "memory"
    return s
}

RuleSpec(note) {
    s := Map(), t := StrLower(note)
    if RegExMatch(t, "^\W*(?:quick\s+)?question\b")
        s["kind"] := "question"
    else if RegExMatch(t, "^\W*(?:think (?:really )?hard\W+(?:and\W+)?)?(?:make |write |draft )?(?:a |the )?plan\b|\bplan (?:out )?(?:a|an|the|my)\b")
        s["kind"] := "plan"
    else if RegExMatch(t, "^\W*(?:please\s+)?(?:fix|implement|refactor|patch)\b|\bfix (?:the|a|this)\b")
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
    else if RegExMatch(t, "\b(?:start fresh|from scratch|new topic)\b")
        s["continue"] := "fresh"

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
    return s
}

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
        for k in ["kind", "workspace", "connectors", "topic", "topic_title"]
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
        '{"kind":"question","workspace":"none","connectors":[],"topic":"new:short-slug","topic_title":"Short title"}',
        "Fields:",
        "- kind: question (answer or explain; no files change), connector (needs an external service from the connector list), code (change files in a project or GitHub repo), plan (design or plan something; the output is only a written plan).",
        "- workspace: project:<name> when the note is about one of the projects (match names loosely; spoken names may lose dashes); clone:<owner/repo> only for a GitHub repo that is not a project; otherwise none.",
        "- connectors: names from the connector list that the job needs, or []. Use new:<name> only when the job needs a service that is not in the list. Asking to be notified (DM me, email me) is not a connector.",
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
    topic := StrLower(GetStr(s, "topic"))
    if !Topics.Has(topic) && !RegExMatch(topic, "^new:[a-z0-9][a-z0-9-]*$")
        topic := "new:" Slug(note)
    s["topic"] := topic
    s["topic_title"] := GetStr(s, "topic_title")
    ask := StrLower(GetStr(s, "ask_policy"))
    s["ask_policy"] := RegExMatch(ask, "^(async|best-guess-after:\d+)$") ? ask : "async"
    cont := StrLower(GetStr(s, "continue"))
    if !Topics.Has(topic)
        cont := "fresh"
    else if !InList(cont, ContinueModes) || (cont = "resume" && Topics[topic].Get("session", "") = "")
        cont := SuggestContinue(topic)
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
