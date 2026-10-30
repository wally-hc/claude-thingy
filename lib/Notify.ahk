NotifyJob(job, res) {
    title := TopicTitle(job["topic"]), status := job["status"]
    head := (status = "failed" ? "Couldn't finish: " : "") title
    line := status = "waiting" ? job["question"] : FirstLine(res)
    body := head "`n" line
    links := FindLinks(res)
    if links.Length
        body .= "`nLinks: " Join(links, " ")
    Deliver(job, head, line, body "`nFull reply: " job["log"])
}

Deliver(job, head, line, body) {
    global LastToastJob
    channel := job["spec"]["notify"], why := ""
    if channel = "slack-dm:me"
        why := SlackPost(Conf("slack.user_token"), body)
    else if channel = "slack-dm:bot"
        why := SlackPost(Conf("slack.bot_token"), body)
    else if channel = "email"
        why := SendEmail("[Claude-thingy] " head, body)
    if channel != "toast" && why = ""
        return
    TrayTip(SubStr(line (why != "" ? "`n(" why ")" : ""), 1, 250), head, job["status"] = "failed" ? 3 : 1)
    LastToastJob := job
}

SlackPost(token, text) {
    user := Conf("slack.user_id")
    if token = "" || user = ""
        return "Slack token or slack.user_id is missing in config.json"
    try {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("POST", "https://slack.com/api/chat.postMessage", false)
        req.SetRequestHeader("Authorization", "Bearer " token)
        req.SetRequestHeader("Content-Type", "application/json; charset=utf-8")
        req.Send(JsonDump(Map("channel", user, "text", text)))
        r := JsonParse(req.ResponseText)
        return r.Get("ok", 0) ? "" : "Slack error: " r.Get("error", "unknown")
    } catch as e
        return "Slack request failed: " e.Message
}

SendEmail(subject, body) {
    smtp := Conf("smtp", Map())
    if !(smtp is Map) || smtp.Get("server", "") = "" || smtp.Get("to", "") = ""
        return "email isn't configured (smtp in config.json)"
    try {
        msg := ComObject("CDO.Message")
        fields := msg.Configuration.Fields
        ns := "http://schemas.microsoft.com/cdo/configuration/"
        fields.Item[ns "sendusing"] := 2
        fields.Item[ns "smtpserver"] := smtp["server"]
        fields.Item[ns "smtpserverport"] := smtp.Get("port", 465)
        fields.Item[ns "smtpusessl"] := ComValue(0xB, smtp.Get("ssl", 1) ? -1 : 0)
        fields.Item[ns "smtpauthenticate"] := 1
        fields.Item[ns "sendusername"] := smtp.Get("user", "")
        fields.Item[ns "sendpassword"] := smtp.Get("password", "")
        fields.Item[ns "smtpconnectiontimeout"] := 30
        fields.Update()
        msg.From := smtp.Get("from", "") != "" ? smtp["from"] : smtp.Get("user", "")
        msg.To := smtp["to"]
        msg.Subject := subject
        msg.BodyPart.Charset := "utf-8"
        msg.TextBody := body
        msg.Send()
    } catch as e
        return "email failed: " e.Message
    return ""
}
