ShowSpecGui(note, spec) {
    g := Gui("+AlwaysOnTop", DryRun ? "Claude-thingy - DRY RUN" : "Claude-thingy")
    g.SetFont("s10", "Segoe UI")
    g.AddText("xm", "Note:")
    noteC := g.AddEdit("xm w620 r6 WantReturn", note)
    wsItems := ["none"]
    for p in Projects
        wsItems.Push("project:" p["name"])
    if SubStr(spec["workspace"], 1, 6) = "clone:"
        wsItems.Push(spec["workspace"])
    topicItems := Topics.Has(spec["topic"]) ? [] : [spec["topic"]]
    for id in Topics
        topicItems.Push(id)
    kindC := SpecRow(g, "Kind", "DDL", Kinds, spec["kind"], true)
    modelC := SpecRow(g, "Model", "DDL", Models, spec["model"])
    wsC := SpecRow(g, "Workspace", "Combo", wsItems, spec["workspace"], true)
    notifyC := SpecRow(g, "Notify", "DDL", Notifiers, spec["notify"])
    topicC := SpecRow(g, "Topic", "Combo", topicItems, spec["topic"], true)
    contC := SpecRow(g, "Continue", "Combo", ContinueModes, spec["continue"])
    connC := SpecRow(g, "Connectors", "Edit", [], Join(spec["connectors"], ", "), true)
    askC := SpecRow(g, "If it asks", "Combo", ["async", "best-guess-after:10", "best-guess-after:30"], spec["ask_policy"])
    accessC := SpecRow(g, "Access", "DDL", ["read", "write"], spec["connector_access"], true)
    g.AddText("x+10 ys+3", "(write = allow changes in connected services)")
    infoC := g.AddText("xm w620", InfoLine(spec["topic"]))
    warnC := g.AddText("xm w620 r3 cB00020", SpecWarning(spec["connectors"], spec["connector_access"], spec["continue"]))
    g.AddButton("xm w160 Default", DryRun ? "Log spec (dry run)" : "Send").OnEvent("Click", SendClicked)
    g.AddButton("x+10 w100", "Cancel").OnEvent("Click", CancelClicked)
    g.OnEvent("Close", CancelClicked)
    g.OnEvent("Escape", CancelClicked)
    st := {kind: spec["kind"]}
    kindC.OnEvent("Change", KindChanged)
    topicC.OnEvent("Change", TopicChanged)
    accessC.OnEvent("Change", WarningChanged)
    connC.OnEvent("Change", WarningChanged)
    contC.OnEvent("Change", WarningChanged)
    g.Show()

    WarningChanged(*) {
        names := []
        for c in SplitList(connC.Value)
            if (name := ConnectorName(c)) != ""
                names.Push(name)
        cont := contC.Value ? ContinueModes[contC.Value] : Trim(contC.Text)
        warnC.Value := SpecWarning(names, accessC.Text, cont)
    }

    KindChanged(*) {
        if modelC.Text = DefaultModel(st.kind)
            modelC.Choose(DefaultModel(kindC.Text))
        st.kind := kindC.Text
    }

    TopicChanged(*) {
        topic := topicC.Value ? topicItems[topicC.Value] : Trim(topicC.Text)
        infoC.Value := InfoLine(topic)
        contC.Choose(SuggestContinue(topic))
        WarningChanged()
    }

    SendClicked(*) {
        text := Trim(noteC.Value)
        if text = ""
            return Notify("The note is empty.", true)
        if Trim(contC.Text) = "session"
            return Notify("Type the session name in Continue as session:<name>, or pick another mode.", true)
        typedTopic := Trim(topicC.Text)
        s := Map("kind", kindC.Text, "model", modelC.Text, "workspace", Trim(wsC.Text), "notify", notifyC.Text
            , "topic", typedTopic, "topic_title", typedTopic = spec["topic"] ? spec["topic_title"] : "", "continue", contC.Text
            , "ask_policy", Trim(askC.Text), "connectors", SplitList(connC.Value)
            , "connector_access", accessC.Text, "routed_by", spec.Get("routed_by", ""))
        s := ValidSpec(s, text)
        g.Destroy()
        if !DryRun
            return StartJob(text, s)
        LogNote(Map("timestamp", Iso(), "status", "dry-run", "transcript", text, "spec", s))
        Notify("Dry run: the spec was logged to notes.jsonl and no job was started.")
    }

    CancelClicked(*) {
        LogNote(Map("timestamp", Iso(), "status", "cancelled", "transcript", noteC.Value, "spec", spec))
        g.Destroy()
    }
}

SpecRow(g, label, type, items, value, newRow := false) {
    g.AddText((newRow ? "xm Section" : "x+20 ys") " w85", label)
    if type = "DDL" {
        ctl := g.AddDropDownList("x+5 ys w210", items)
        try ctl.Choose(value)
    } else if type = "Combo" {
        ctl := g.AddComboBox("x+5 ys w210", items)
        ctl.Text := value
    } else
        ctl := g.AddEdit("x+5 ys w210", value)
    return ctl
}

ShowReplyGui(job) {
    g := Gui("+AlwaysOnTop +ToolWindow", "Answer: " TopicTitle(job["topic"]))
    g.SetFont("s10", "Segoe UI")
    g.AddText("w440", job["question"])
    answerC := g.AddEdit("w440 r4 WantReturn")
    g.AddButton("w100 Default", "Send").OnEvent("Click", Submit)
    g.AddButton("x+10 w100", "Later").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show("NoActivate")

    Submit(*) {
        text := Trim(answerC.Value)
        if text = ""
            return
        g.Destroy()
        if job["status"] = "waiting"
            AnswerJob(job, text)
    }
}

ShowPicker(list, answer) {
    g := Gui("+AlwaysOnTop", "Which job is this answer for?")
    g.SetFont("s10", "Segoe UI")
    items := []
    for job in list
        items.Push(TopicTitle(job["topic"]) ": " SubStr(job["question"], 1, 90))
    pickC := g.AddListBox("w560 r" Min(list.Length, 8) " Choose1", items)
    g.AddButton("w100 Default", "Answer").OnEvent("Click", Pick)
    g.AddButton("x+10 w100", "Cancel").OnEvent("Click", (*) => g.Destroy())
    g.OnEvent("Escape", (*) => g.Destroy())
    g.Show()

    Pick(*) {
        chosen := list[pickC.Value]
        g.Destroy()
        if answer != ""
            AnswerJob(chosen, answer)
        else
            ShowReplyGui(chosen)
    }
}
