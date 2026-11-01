#Requires AutoHotkey v2.0
#SingleInstance Off
Persistent
SetWorkingDir A_ScriptDir
#Include lib\Core.ahk
#Include lib\Dispatch.ahk
#Include lib\Jobs.ahk
#Include lib\Notify.ahk
#Include lib\Gui.ahk
#Include lib\Dashboard.ahk

global Rec := "", RecGui := ""
wantDashboard := InList("/dashboard", A_Args)
DetectHiddenWindows(true)
for hwnd in WinGetList(A_ScriptFullPath " - AutoHotkey ahk_class AutoHotkey") {
    if hwnd = A_ScriptHwnd
        continue
    if wantDashboard {
        PostMessage(0x8001, 1, 0, , hwnd)
        ExitApp()
    }
    PostMessage(0x8001, 2, 0, , hwnd)
    WinWaitClose(hwnd, , 5)
}
DetectHiddenWindows(false)
OnMessage(0x8001, AppMessage)

if FileExist(IconPath)
    TraySetIcon(IconPath)
JobsMenu := Menu()
A_TrayMenu.Delete()
A_TrayMenu.Add("Dashboard", ShowDashboard)
A_TrayMenu.Default := "Dashboard"
A_TrayMenu.Add("Jobs", JobsMenu)
A_TrayMenu.Add("Open last result", OpenLastResult)
A_TrayMenu.Add("Open data folder", (*) => Run(DataDir))
A_TrayMenu.Add("Sign in to connectors", (*) => LoadConfig() && ConnectorSignIn(ConnectorKeys()))
A_TrayMenu.Add(DryRunItem, ToggleDryRun)
A_TrayMenu.Add("Add desktop shortcut", CreateDesktopShortcut)
A_TrayMenu.Add("Reload", (*) => Reload())
A_TrayMenu.Add("Exit", (*) => ExitApp())
OnMessage(0x404, TrayEvent)

configOk := LoadConfig()
HotkeyLabel := RegisterHotkey()
A_IconTip := "Claude-thingy " AppVersion " (" HotkeyLabel ")"
if configOk
    Notify("Ready. Press " HotkeyLabel " to record a note.")
if Conf("dry_run", 0)
    ToggleDryRun()
LoadJobs()
RebuildJobsMenu()
SetTimer(PollJobs, 3000)
if wantDashboard
    ShowDashboard()

AppMessage(wParam, *) {
    if wParam = 1
        SetTimer(ShowDashboard, -10)
    else if wParam = 2
        ExitApp()
    return 1
}

RegisterHotkey() {
    hk := Conf("hotkey", "^!+j")
    try Hotkey(hk, (*) => ToggleRecording())
    catch {
        Notify("The `"hotkey`" in config.json isn't valid, so Ctrl+Alt+Shift+J is used instead.", true)
        hk := "^!+j"
        Hotkey(hk, (*) => ToggleRecording())
    }
    return HotkeyName(hk)
}

HotkeyName(hk) {
    names := Map("#", "Win+", "^", "Ctrl+", "!", "Alt+", "+", "Shift+")
    mods := ""
    while RegExMatch(hk, "^[#^!+<>*~$]", &m) {
        mods .= names.Get(m[0], "")
        hk := SubStr(hk, 2)
    }
    return mods StrUpper(SubStr(hk, 1, 1)) SubStr(hk, 2)
}

ToggleRecording() {
    global Rec, RecGui
    if Rec
        return StopAndTranscribe()
    if !LoadConfig()
        return
    mic := Cfg["mic"] != "" ? Cfg["mic"] : FindMic()
    if mic = ""
        return Notify("No microphone found. Set `"mic`" in config.json (see README).", true)
    wav := TempDir "\" A_Now ".wav"
    Run('"' Cfg["ffmpeg"] '" -hide_banner -loglevel error -f dshow -i audio="' mic '" -ar 16000 -ac 1 -y "' wav '"', , "Hide", &pid)
    Sleep 800
    if !ProcessExist(pid)
        return Notify('Could not record from mic "' mic '". Check the "mic" name in config.json.', true)
    Rec := {pid: pid, wav: wav}
    if Conf("sounds", 1)
        SoundBeep(880, 120)
    RecGui := Gui("+AlwaysOnTop -Caption +ToolWindow")
    RecGui.BackColor := "B00020"
    RecGui.SetFont("s10 bold cWhite", "Segoe UI")
    RecGui.AddText(, "Recording...  (" HotkeyLabel " to stop)")
    RecGui.Show("NoActivate x20 y20")
    if (limit := Conf("max_record_seconds", 180)) > 0
        SetTimer(AutoStop.Bind(wav), -limit * 1000)
}

AutoStop(wav) {
    if !IsObject(Rec) || Rec.wav != wav
        return
    Notify("Recording stopped at the time limit.")
    StopAndTranscribe()
}

StopAndTranscribe() {
    global Rec, RecGui
    r := Rec, Rec := ""
    RecGui.Destroy()
    if Conf("sounds", 1)
        SoundBeep(440, 120)
    StopConsoleProcess(r.pid)
    if !FileExist(r.wav)
        return Notify("Recording failed: no audio file was written.", true)
    Notify("Transcribing...")
    base := SubStr(r.wav, 1, -4)
    code := RunWait('"' Cfg["whisper"] '" -m "' Cfg["model"] '" -f "' r.wav '" -nt -np -otxt -of "' base '"', , "Hide")
    text := FileExist(base ".txt") ? FileRead(base ".txt", "UTF-8") : ""
    try FileDelete(r.wav)
    try FileDelete(base ".txt")
    if code != 0
        return Notify("Transcription failed (whisper-cli exit code " code "). Check the whisper/model paths.", true)
    text := Trim(RegExReplace(RegExReplace(text, "\[BLANK_AUDIO\]"), "\s*\R\s*", " "))
    if text = ""
        return Notify("Empty transcript (nothing heard?), nothing to send.", true)
    HandleNote(text)
}

HandleNote(text) {
    if RegExMatch(text, "i)^\W*answer\b[\s,.:;!-]*(.*)$", &m) {
        waiting := WaitingJobs()
        if waiting.Length = 1
            return m[1] != "" ? AnswerJob(waiting[1], m[1]) : ShowReplyGui(waiting[1])
        if waiting.Length > 1
            return ShowPicker(Reversed(waiting), m[1])
        Notify("No job is waiting for an answer, so this is treated as a new note.")
    }
    Notify("One moment...")
    ShowSpecGui(text, Route(text))
}

StopConsoleProcess(pid) {
    if attached := DllCall("AttachConsole", "UInt", pid) {
        DllCall("SetConsoleCtrlHandler", "Ptr", 0, "Int", 1)
        DllCall("GenerateConsoleCtrlEvent", "UInt", 0, "UInt", 0)
    }
    if ProcessWaitClose(pid, 5)
        ProcessClose(pid)
    if attached {
        DllCall("SetConsoleCtrlHandler", "Ptr", 0, "Int", 0)
        DllCall("FreeConsole")
    }
}

FindMic() {
    static found := ""
    if found != ""
        return found
    out := TempDir "\devices.txt"
    RunWait(A_ComSpec ' /s /c ""' Cfg["ffmpeg"] '" -hide_banner -list_devices true -f dshow -i dummy 2> "' out '""', , "Hide")
    text := FileExist(out) ? FileRead(out, "UTF-8") : ""
    return found := RegExMatch(text, '"([^"]+)" \(audio\)', &m) ? m[1] : ""
}

TrayEvent(wParam, lParam, *) {
    if (lParam & 0xFFFF) != 0x405 || !IsObject(LastToastJob)
        return
    if LastToastJob["status"] = "waiting"
        ShowReplyGui(LastToastJob)
    else if FileExist(LastToastJob.Get("log", ""))
        OpenFile(LastToastJob["log"])
}

