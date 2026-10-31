global AppVersion := "0.1.0"
global Cfg := Map(), Projects := [], Connectors := Map(), Topics := Map(), Jobs := []
global DryRun := false, CliMode := false, LastLog := "", LastToastJob := "", JobsMenu := "", RouteError := ""
global TempDir := A_Temp "\claude-thingy", ConfigDir := A_ScriptDir "\config", ConnectorsPath := ConfigDir "\connectors.json"
global WorkDir := EnvGet("LOCALAPPDATA") "\claude-thingy\workspaces"
global DataDir := "", LogDir := "", TopicDir := "", BriefingPath := "", JobsPath := ""
global Kinds := ["question", "connector", "code", "plan"], Models := ["haiku", "sonnet", "opus"]
global Notifiers := ["toast", "email", "slack-dm:me", "slack-dm:bot"], ContinueModes := ["resume", "memory", "fresh", "session"]
DirCreate(TempDir), SetDataDir(A_ScriptDir "\data")

SetDataDir(dir) {
    global DataDir := dir, LogDir := dir "\logs", TopicDir := dir "\topics"
    global BriefingPath := TopicDir "\briefing.md", JobsPath := LogDir "\jobs.json"
    DirCreate(LogDir), DirCreate(TopicDir)
}

LoadConfig() {
    global Cfg, Projects, Connectors
    try {
        Cfg := JsonParse(FileRead(ConfigDir "\config.json", "UTF-8"))
        Projects := FileExist(ConfigDir "\projects.json") ? JsonParse(FileRead(ConfigDir "\projects.json", "UTF-8")) : []
        Connectors := FileExist(ConnectorsPath) ? JsonParse(FileRead(ConnectorsPath, "UTF-8")) : Map()
    } catch as e
        return (Notify("Could not read config\config.json / projects.json / connectors.json: " e.Message, true), false)
    if !(Projects is Array) || !(Connectors is Map)
        return (Notify("projects.json must be a list and connectors.json an object.", true), false)
    for key in ["ffmpeg", "whisper", "model"] {
        path := Resolve(Conf(key))
        if path = ""
            return (Notify('Missing dependency: "' key '" not found. Check the path in config.json.', true), false)
        Cfg[key] := path
    }
    Cfg["mic"] := Conf("mic")
    Cfg["claude"] := Conf("claude") != "" ? Cfg["claude"] : "claude"
    dir := Conf("data_dir", "data")
    SetDataDir(RegExMatch(dir, "^(?:[A-Za-z]:|\\\\)") ? dir : A_ScriptDir "\" dir)
    LoadTopics()
    return true
}

Conf(path, default := "") {
    v := Cfg
    for key in StrSplit(path, ".") {
        if !(v is Map) || !v.Has(key)
            return default
        v := v[key]
    }
    return v
}

Resolve(p) {
    if p != "" && FileExist(p)
        return p
    if p != ""
        Loop Parse EnvGet("PATH"), ";"
            if A_LoopField != "" && FileExist(A_LoopField "\" p)
                return A_LoopField "\" p
    return ""
}

LoadTopics() {
    global Topics := Map()
    try {
        for t in JsonParse(FileRead(TopicDir "\index.json", "UTF-8"))
            Topics[t["id"]] := t
    }
}

SaveTopics() {
    list := []
    for id, t in Topics
        list.Push(t)
    FileWriteNew(TopicDir "\index.json", JsonDump(list, true))
}

RecentTopics(count) {
    keys := ""
    for id, t in Topics
        keys .= t.Get("last", "") "`t" id "`n"
    list := []
    Loop Parse Sort(RTrim(keys, "`n"), "R"), "`n"
        if A_LoopField != "" && list.Length < count
            list.Push(Topics[StrSplit(A_LoopField, "`t")[2]])
    return list
}

MemoryPath(id) => TopicDir "\" id "\memory.md"
ConversationPath(id) => TopicDir "\" id "\conversation.md"
TopicTitle(id) => Topics.Has(id) ? Topics[id]["title"] : RegExReplace(id, "^new:")

CanResume(t) {
    return t.Get("session", "") != "" && DirExist(t.Get("folder", ""))
        && DaysAgo(t.Get("last", "")) <= Conf("resume_max_days", 3)
        && t.Get("size", 0) <= Conf("resume_max_tokens", 80000)
}

DaysAgo(iso) {
    digits := RegExReplace(iso, "\D")
    return StrLen(digits) = 14 ? DateDiff(A_Now, digits, "Days") : 9999
}

Iso(ts := "") {
    ts := ts = "" ? A_Now : ts
    return FormatTime(ts, "yyyy-MM-dd") "T" FormatTime(ts, "HH:mm:ss")
}

Slug(text) {
    words := StrSplit(Trim(RegExReplace(StrLower(text), "[^a-z0-9]+", "-"), "-"), "-")
    picked := []
    for w in words
        if picked.Length < 5 && w != ""
            picked.Push(w)
    return picked.Length ? SubStr(Join(picked, "-"), 1, 40) : "note"
}

Join(list, sep) {
    s := ""
    for x in list
        s .= (A_Index > 1 ? sep : "") x
    return s
}

SplitList(text) {
    list := []
    Loop Parse text, ","
        if Trim(A_LoopField) != ""
            list.Push(Trim(A_LoopField))
    return list
}

Reversed(list) {
    out := []
    Loop list.Length
        out.Push(list[list.Length - A_Index + 1])
    return out
}

InList(v, list) {
    for x in list
        if x = v
            return true
    return false
}

FirstLine(text) {
    Loop Parse text, "`n", "`r"
        if Trim(A_LoopField) != ""
            return SubStr(Trim(A_LoopField), 1, 200)
    return "(no output)"
}

FindLinks(text) {
    found := [], pos := 1
    while RegExMatch(text, "https?://[^\s<>()\[\]`"'``]+", &m, pos) {
        url := RegExReplace(m[0], "[.,;:!?*]+$"), pos := m.Pos + m.Len
        if !InList(url, found) && found.Length < 5
            found.Push(url)
    }
    return found
}

FileWriteNew(path, text) {
    tmp := path ".tmp"
    try FileDelete(tmp)
    FileAppend(text, tmp, "UTF-8-RAW")
    Loop 5 {
        try {
            FileMove(tmp, path, 1)
            return
        }
        Sleep 200
    }
    FileMove(tmp, path, 1)
}

ReadIf(path) => FileExist(path) ? FileRead(path, "UTF-8") : ""

RunCapture(cmd, cwd := "") {
    out := TempDir "\capture.txt"
    try FileDelete(out)
    RunWait(A_ComSpec ' /s /c "' cmd ' > "' out '" 2>&1"', cwd, "Hide")
    return Trim(ReadIf(out), " `t`r`n")
}

OpenFile(path) {
    try Run(path)
    catch
        Run('notepad.exe "' path '"')
}

Notify(msg, isError := false) {
    global LastToastJob := ""
    if CliMode
        return FileAppend(msg "`n", "*", "UTF-8")
    TrayTip(msg, "Claude-thingy", isError ? 3 : 1)
}

LogNote(fields) => FileAppend(JsonDump(fields) "`n", LogDir "\notes-" FormatTime(, "yyyy-MM") ".jsonl", "UTF-8-RAW")

JsonStr(s) {
    s := StrReplace(StrReplace(String(s), "\", "\\"), '"', '\"')
    s := StrReplace(StrReplace(StrReplace(s, "`r", "\r"), "`n", "\n"), "`t", "\t")
    out := "", pos := 1
    while RegExMatch(s, "[^ -~]+", &m, pos) {
        out .= SubStr(s, pos, m.Pos - pos), chars := m[0]
        Loop StrLen(chars)
            out .= Format("\u{:04x}", NumGet(StrPtr(chars), (A_Index - 1) * 2, "UShort"))
        pos := m.Pos + m.Len
    }
    return '"' out SubStr(s, pos) '"'
}

JsonDump(v, pretty := false, pad := "") {
    if !(v is Map || v is Array)
        return v is Number ? String(v) : JsonStr(v)
    s := "", inner := pad "  "
    for k, x in v
        s .= (A_Index > 1 ? "," : "") (pretty ? "`n" inner : "") (v is Map ? JsonStr(k) (pretty ? ": " : ":") : "") JsonDump(x, pretty, inner)
    return (v is Map ? "{" : "[") s (pretty && s != "" ? "`n" pad : "") (v is Map ? "}" : "]")
}

ParseJsonIn(text) {
    if !(p := InStr(text, "{"))
        throw Error("no JSON in output")
    return JsonParse(SubStr(text, p))
}

JsonParse(s, &i := 1) {
    RegExMatch(s, "\G\s*", &m, i), i += m.Len
    c := SubStr(s, i, 1)
    if c = "{" || c = "[" {
        obj := c = "{" ? Map() : [], close := c = "{" ? "}" : "]", i++
        Loop {
            RegExMatch(s, "\G\s*", &m, i), i += m.Len
            if SubStr(s, i, 1) = close
                return (i++, obj)
            if c = "{" {
                key := JsonParse(s, &i)
                if !RegExMatch(s, "\G\s*:", &m, i)
                    throw Error("expected ':' at position " i)
                i += m.Len
                obj[key] := JsonParse(s, &i)
            } else
                obj.Push(JsonParse(s, &i))
            RegExMatch(s, "\G\s*,?", &m, i), i += m.Len
        }
    }
    if c = '"' {
        j := i
        Loop {
            if !(j := InStr(s, '"', true, j + 1))
                throw Error("unterminated string at position " i)
            k := j - 1
            while SubStr(s, k, 1) = "\"
                k--
            if Mod(j - 1 - k, 2) = 0
                break
        }
        str := SubStr(s, i + 1, j - i - 1), i := j + 1, out := "", pos := 1
        while RegExMatch(str, "\\(u[0-9a-fA-F]{4}|.)", &e, pos) {
            k := e[1]
            out .= SubStr(str, pos, e.Pos - pos)
                . (StrLen(k) = 5 ? Chr(Integer("0x" SubStr(k, 2))) : k == "n" ? "`n" : k == "t" ? "`t" : k == "r" ? "`r" : k)
            pos := e.Pos + e.Len
        }
        return out SubStr(str, pos)
    }
    if RegExMatch(s, "\G(true|false|null|-?[\d.eE+-]+)", &m, i) {
        i += m.Len
        return m[1] == "true" ? 1 : m[1] == "false" ? 0 : m[1] == "null" ? "" : m[1] + 0
    }
    throw Error("invalid JSON at position " i)
}
