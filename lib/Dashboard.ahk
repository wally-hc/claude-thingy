global Dash := ""

ShowDashboard(*) {
    if !IsObject(Dash)
        BuildDashboard()
    RefreshDashboard()
    Dash.g.Show()
    WinActivate("ahk_id " Dash.g.Hwnd)
}

BuildDashboard() {
    global Dash
    g := Gui("+Resize +MinSize720x480", "Claude-thingy")
    g.SetFont("s10", "Segoe UI")
    d := {g: g, recentJobs: [], jobList: [], topicList: []}
    d.tab := g.AddTab3("x8 y8 w784 h504", ["Home", "Jobs", "Topics", "Settings"])
    d.tab.UseTab("Home")
    BuildHomePage(g, d)
    d.tab.UseTab("Jobs")
    BuildJobsPage(g, d)
    d.tab.UseTab("Topics")
    BuildTopicsPage(g, d)
    d.tab.UseTab("Settings")
    BuildSettingsPage(g, d)
    d.tab.UseTab()
    g.OnEvent("Escape", (*) => g.Hide())
    g.OnEvent("Size", DashResize)
    SetWindowIcon(g.Hwnd)
    g.Show("w800 h520 Hide")
    Dash := d
}

BuildHomePage(g, d) {
    g.SetFont("s20 bold")
    d.running := g.AddText("x24 y52 w170 Center", "0")
    d.waiting := g.AddText("x+10 yp w170 Center", "0")
    d.today := g.AddText("x+10 yp w170 Center", "0")
    d.cost := g.AddText("x+10 yp w170 Center", "$0.00")
    g.SetFont("s9 norm cGray")
    g.AddText("x24 y+0 w170 Center", "running")
    g.AddText("x+10 yp w170 Center", "waiting for you")
    g.AddText("x+10 yp w170 Center", "jobs today")
    g.AddText("x+10 yp w170 Center", "cost this month")
    g.SetFont("s10 norm cDefault")
    g.AddButton("x24 y+16 w170", "New voice note").OnEvent("Click", (*) => %"ToggleRecording"%())
    g.AddButton("x+10 yp w170", "Open last result").OnEvent("Click", OpenLastResult)
    d.recent := g.AddListView("x24 y+12 w740 h280 -Multi", ["When", "Topic", "Status", "Summary"])
    d.recent.OnEvent("DoubleClick", (lv, row) => row && JobClicked(d.recentJobs[row]))
}

BuildJobsPage(g, d) {
    g.AddButton("x24 y48 w170", "Open conversation").OnEvent("Click", (*) => (job := SelectedJob()) && OpenIfExists(job.Get("log", "")))
    g.AddButton("x+8 yp w100", "Answer").OnEvent("Click", (*) => (job := SelectedJob()) && (job["status"] = "waiting" ? ShowReplyGui(job) : Notify("That job isn't waiting for an answer.")))
    g.AddButton("x+8 yp w100", "Stop").OnEvent("Click", (*) => (job := SelectedJob()) && JobClicked(job))
    d.jobs := g.AddListView("x24 y+10 w740 h400 -Multi", ["Status", "Topic", "Kind", "Workspace", "Started"])
    d.jobs.OnEvent("DoubleClick", (lv, row) => row && JobClicked(d.jobList[row]))
}

BuildTopicsPage(g, d) {
    g.AddButton("x24 y48 w170", "Open conversation").OnEvent("Click", (*) => (id := SelectedTopic()) != "" && OpenIfExists(ConversationPath(id)))
    g.AddButton("x+8 yp w140", "Open memory").OnEvent("Click", (*) => (id := SelectedTopic()) != "" && OpenIfExists(MemoryPath(id)))
    d.topics := g.AddListView("x24 y+10 w740 h400 -Multi", ["Topic", "Last used", "Workspace", "Summary"])
    d.topics.OnEvent("DoubleClick", (lv, row) => row && OpenIfExists(ConversationPath(d.topicList[row])))
}

BuildSettingsPage(g, d) {
    d.version := g.AddText("x24 y52 w740", "")
    d.dry := g.AddCheckbox("x24 y+16", "Dry run: route notes but don't start jobs")
    d.dry.OnEvent("Click", ToggleDryRun)
    g.AddText("x24 y+20", "Settings files")
    g.AddButton("x24 y+6 w170", "config.json").OnEvent("Click", (*) => OpenIfExists(ConfigDir "\config.json"))
    g.AddButton("x+8 yp w170", "projects.json").OnEvent("Click", (*) => OpenIfExists(ConfigDir "\projects.json"))
    g.AddButton("x+8 yp w170", "connectors.json").OnEvent("Click", (*) => OpenIfExists(ConnectorsPath))
    g.AddButton("x+8 yp w170", "instructions.md").OnEvent("Click", (*) => OpenIfExists(ConfigDir "\instructions.md"))
    g.AddText("x24 y+20", "Tools")
    g.AddButton("x24 y+6 w170", "Sign in to connectors").OnEvent("Click", (*) => LoadConfig() && ConnectorSignIn(ConnectorKeys()))
    g.AddButton("x+8 yp w170", "Open data folder").OnEvent("Click", (*) => Run(DataDir))
    g.AddButton("x+8 yp w170", "Add desktop shortcut").OnEvent("Click", CreateDesktopShortcut)
    g.AddButton("x+8 yp w170", "Reload").OnEvent("Click", (*) => Reload())
}

RefreshDashboard() {
    if !IsObject(Dash)
        return
    d := Dash, running := 0, waiting := 0, today := 0
    for job in Jobs {
        running += job["status"] = "running"
        waiting += job["status"] = "waiting"
        today += SubStr(job.Get("started", ""), 1, 8) = SubStr(A_Now, 1, 8)
    }
    d.running.Value := running, d.waiting.Value := waiting, d.today.Value := today
    d.cost.Value := "$" Format("{:.2f}", MonthCost())

    d.jobList := Reversed(Jobs), d.recentJobs := []
    d.recent.Delete(), d.jobs.Delete()
    for job in d.jobList {
        when := job.Get("started", "") != "" ? FormatTime(job["started"], "MMM d HH:mm") : ""
        title := TopicTitle(job["topic"])
        d.jobs.Add(, job["status"], title, job["spec"]["kind"], job["spec"]["workspace"], when)
        if d.recentJobs.Length < 10 {
            d.recentJobs.Push(job)
            summary := Topics.Has(job["topic"]) ? Topics[job["topic"]].Get("summary", "") : ""
            d.recent.Add(, when, title, job["status"], SubStr(job["status"] = "waiting" ? job["question"] : summary, 1, 90))
        }
    }
    d.topicList := [], d.topics.Delete()
    for t in RecentTopics(500) {
        d.topicList.Push(t["id"])
        last := t.Get("last", "") != "" ? SubStr(t["last"], 1, 10) : "not run yet"
        d.topics.Add(, t["title"], last, t.Get("workspace", ""), SubStr(t.Get("summary", ""), 1, 90))
    }
    for lv in [d.recent, d.jobs, d.topics]
        lv.ModifyCol()
    d.version.Value := "Claude-thingy " AppVersion "    Hotkey: " HotkeyLabel "    Data: " DataDir
    d.dry.Value := DryRun
}

DashResize(g, minMax, w, h) {
    if minMax = -1 || !IsObject(Dash)
        return
    Dash.tab.Move(, , w - 16, h - 16)
    for lv in [Dash.recent, Dash.jobs, Dash.topics] {
        lv.GetPos(&x, &y)
        lv.Move(, , w - x - 24, h - y - 24)
    }
}

SelectedJob() {
    row := Dash.jobs.GetNext(0)
    return row ? Dash.jobList[row] : (Notify("Select a job first."), "")
}

SelectedTopic() {
    row := Dash.topics.GetNext(0)
    return row ? Dash.topicList[row] : (Notify("Select a topic first."), "")
}

OpenIfExists(path) => FileExist(path) ? OpenFile(path) : Notify("There's nothing there yet.")

MonthCost() {
    total := 0, path := LogDir "\notes-" FormatTime(, "yyyy-MM") ".jsonl"
    if !FileExist(path)
        return 0
    Loop Read path
        if RegExMatch(A_LoopReadLine, '"cost_usd":([\d.eE+-]+)', &m)
            total += m[1]
    return total
}

SetWindowIcon(hwnd) {
    if !FileExist(IconPath)
        return
    for size in [16, 32] {
        icon := LoadPicture(IconPath, "Icon1 w" size " h" size, &type)
        SendMessage(0x80, size = 16 ? 0 : 1, icon, , hwnd)
    }
}

CreateDesktopShortcut(*) {
    link := A_Desktop "\Claude-thingy.lnk"
    FileCreateShortcut(A_AhkPath, link, A_ScriptDir, '"' A_ScriptDir '\Claude-thingy.ahk" /dashboard', "Claude-thingy dashboard", IconPath)
    Notify("Added Claude-thingy to your desktop. To pin it, right-click it, choose Show more options, then Pin to taskbar.")
}
