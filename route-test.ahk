#Requires AutoHotkey v2.0
#SingleInstance Off
#NoTrayIcon
SetWorkingDir A_ScriptDir
#Include lib\Core.ahk
#Include lib\Dispatch.ahk
#Include lib\Jobs.ahk
#Include lib\Notify.ahk
#Include lib\Gui.ahk

CliMode := true
if !LoadConfig()
    ExitApp(1)
for note in A_Args {
    spec := Route(note)
    FileAppend(JsonDump(Map("note", note, "spec", spec, "info", InfoLine(spec["topic"])), true) "`n", "*", "UTF-8")
}
ExitApp(0)
