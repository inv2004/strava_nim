{.experimental: "codeReordering".}

import oauth2
import httpclient
import uri
import asyncdispatch
import asynchttpserver
import asyncfile
import json
import sequtils
import strutils
import tables
import sugar
import strformat
import logging

import storage
import times
import analytic

type
    MyError* = object of Exception

const
    httpHost = "strava-nim.tradesim.org"
    httpPort = 8090
    #clientId = "438197548914-kp6b5mu5543gdinspvt5tgj0s71q1vbv.apps.googleusercontent.com"
    clientId = "438197548914-rd4afdt82qk0hd9qntp8bg2cd1pprp5v.apps.googleusercontent.com"
    #clientSecret = "F3FV-r9obIVHG3gW6JvDP95m"
    clientSecret = "cGtgJ69WgFJejypLUzxCoTFA"
    clientScope = @["https://www.googleapis.com/auth/spreadsheets", "email"]
    authorizeUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    accessTokenUrl = "https://accounts.google.com/o/oauth2/token"
    redirectUri = "http://" & httpHost & ":" & $httpPort
    sheetApi = "https://sheets.googleapis.com/v4/spreadsheets"
    userinfoApi = "https://www.googleapis.com/userinfo/v2/me"
    stravaClientId = "18057"
    stravaClientSecret = "05e15bf725a7c4ee80fcd6683c8bebd5a5811cef"
    stravaClientScope = @["activity:read_all"]
    stravaAuthorizeUrl = "http://www.strava.com/oauth/authorize"
    stravaAccessTokenUrl = "https://www.strava.com/oauth/token"
    stravaApi = "https://www.strava.com/api/v3"
    stravaPageLimit = 100

var server = newAsyncHttpServer()

let client = newAsyncHttpClient()

proc email_test(accessToken: string): Future[(string, string)] {.async.} =
    let res = await client.bearerRequest(userinfoApi, accessToken)
    let body = await res.body()

    let j = parseJson(body)

    return (j["id"].getStr, j["email"].getStr)


proc sheet_test(sheetId: string, accessToken: string): Future[string] {.async.} =
    let valueRange = "A1:E10"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" &
            valueRange & "?majorDimension=ROWS", accessToken)
    let body = await res.body()
    let j = parseJson(body)

    proc to_html(j: JsonNode): string =
        j.getElems().map(proc (x: JsonNode): string = "<td>"&x.getStr()&"</td>").join()

    return "<table border=2><tr>" & j["values"].getElems().map(to_html).join(
            "</tr><tr>") & "</tr></table>"

proc parseQuery(query: string): TableRef[string, string] =
    let responses = query.split("&")
    result = newTable[string, string]()
    for response in responses:
        let fd = response.find("=")
        result[response[0..fd-1]] = response[fd+1..len(response)-1].decodeUrl()

proc http_handler*(req: Request) {.async, gcsafe.} =
    var headers = newHttpHeaders([("Cache-Control", "no-cache")])
    headers["Content-Type"] = "text/html; charset=utf-8"

    if req.url.path == "/":
        let msg = """
<HTML>Click here to start authorisation <a href="/gauth">Google Auth</a></HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/gauth":
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            authorizeUrl,
            clientId,
            redirectUri & "/gcode",
            state,
            clientScope,
            accessType = "offline"
        )
        headers["Location"] = grantUrl
        await req.respond(Http301, "", headers)
    elif req.url.path == "/gcode":
        let grantResponse = req.url.parseAuthorizationResponse()

        # echo "Code is " & grantResponse.code

        let sheetId = "1oo_BljdsPXQC296TXY9h_vYgkrRhWQDul16yk0-6qGI"

        let msg = """
<HTML><form action="/check_sheet">spreadsheet id:
    <input type="text" name="sheet_id" value="""" & sheetId &
                """" size="60"/>
    <input type="hidden" name="code" value="""" & grantResponse.code & """"/>
    <input type="submit" value="check"/>
</form></HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/check_sheet":
        let params = req.url.query.parseQuery()
        let resp = await client.getAuthorizationCodeAccessToken(
            accessTokenUrl,
            params["code"],
            clientId,
            clientSecret,
            redirectUri & "/gcode",
            useBasicAuth = false
        )
        let body = await resp.body()
        let j = parseJson(body)
        debug j
        if not j.contains("access_token"): raise newException(MyError, "No access_token found from google")
        if not j.contains("expires_in"): raise newException(MyError, "No expires_in found from google")

        if not j.contains("refresh_token"):
            await req.respond(Http200, """
<HTML>No refresh_token found in google response.<br>
    Please remove strava-nim permissions from <a href="https://myaccount.google.com/u/0/permissions">https://myaccount.google.com/u/0/permissions</a>
    And try again: <a href="/">Restart</a></HTML>
""", headers)
            return

        let accessToken = j["access_token"].getStr()

        let profile = await email_test(accessToken)
        let uid = profile[0]
            # let email = profile[1]

        store(profile, accessToken)
        upd_store(uid, "refresh_token", j["refresh_token"].getStr)
        let exp = (getTime() + initDuration(seconds = j[
                "expires_in"].getInt)).toUnix()
        upd_store(uid, "expiration", $exp)
        upd_store(uid, "sheet_id", params["sheet_id"])

        let res2 = await sheet_test(params["sheet_id"], accessToken)
        let msg = """
<HTML>Ok:<br/>""" & res2 & """
<p/>
<a href="/sauth?uid=""" & uid & """">Strava Auth</a>
</HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/sauth":
        let params = req.url.query.parseQuery()
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            stravaAuthorizeUrl,
            stravaClientId,
            redirectUri & "/scode?uid=" & params["uid"],
            state,
            stravaClientScope,
            accessType = "offline"
        )
        headers["Location"] = grantUrl
        await req.respond(Http301, "", headers)
    elif req.url.path == "/scode":
        let params = req.url.query.parseQuery()
        let uid = params["uid"]
        # echo $params
        let resp = await client.getAuthorizationCodeAccessToken(
            stravaAccessTokenUrl,
            params["code"],
            stravaClientId,
            stravaClientSecret,
            redirectUri & "/scode?uid=" & params["uid"],
            useBasicAuth = false
        )
        let body = await resp.body()
        let j = parseJson(body)
        debug j
        if j.contains("access_token") and j.contains("refresh_token") and
                j.contains("expires_in"):
            upd_store(uid, "strava_access_token", j["access_token"].getStr)
            upd_store(uid, "strava_refresh_token", j["refresh_token"].getStr)
            let exp = (getTime() + initDuration(seconds = j[
                    "expires_in"].getInt)).toUnix()
            upd_store(uid, "strava_expiration", $exp)

            let athlete = j["athlete"]
            let msg = """
<HTML>
Ok<br/>Hello """ & athlete["firstname"].getStr() & " " & athlete[
                    "lastname"].getStr() &
                    """
<p/>
<a href="/process?uid=""" & params["uid"] & """">Process The Day</a>
</HTML>
"""
            await req.respond(Http200, msg, headers)
        else:
            await req.respond(Http200, "<HTML>Error. <a href=\"/\">Restart</a></HTML>", headers)
    elif req.url.path == "/process":
        let params = req.url.query.parseQuery()
        let uid = params["uid"]

        # let today = now() - initDuration(days = 3)
        let today = initDateTime(30, mJan, 2020, 0, 0, 0, utc())

        let (plan, _, _) = await getPlan(uid, today)
        let (activity, tw) = await getActivity(uid, today)

        let pattern = normalize_plan(plan)
        let res = pattern.process(tw["time"], tw["watts"])

        let msg = """
<HTML>
    Example:
    <table border=3>
        <tr><td>Today:</td><td>""" & today.format("YYYY-MM-dd") &
                """</td></tr>
        <tr><td>Plan:</td><td>""" & plan &
                """</td></tr>
        <tr><td>Activity:</td><td>""" & activity &
                """</td></tr>
        <tr><td>Activity:</td><td>""" & $res & """</td></tr>
    </table>
    Your auth is saved and will be processes automatically
</HTML>
"""
        await req.respond(Http200, msg, headers)
    else:
        await req.respond(Http404, "Not Found")

proc getPlan(uid: string, dt: DateTime): Future[(string, int, string)] {.async.} =
    debug "Requesting current plan"
    let accessToken = get_store(uid, "access_token")
    let sheetId = get_store(uid, "sheet_id")

    let valueRange = "A:J"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" &
            valueRange & "?majorDimension=ROWS", accessToken)
    let body = await res.body()
    let j = parseJson(body)

    let today_str = dt.format("M/d/YYYY")

    proc mapDate(x: JsonNode): string =
        let row = x.getElems()
        if row.len > 0:
            row[0].getStr("")
        else:
            ""

    let elems = j["values"].getElems()
    let idx = elems.mapIt(it.mapDate()).find(today_str)

    # let foundDates = j["values"].getElems().filter(checkFirst)
    if idx == -1:
        raise newException(MyError, "No records found in sheet")

    debug "Current day found in plan"

    let currentDay = elems[idx][4].getStr
    let text = if elems[idx].len >= 10: elems[idx][9].getStr else: ""
    let idx2 = idx + 1

    info "Current plan: " & currentDay & "    row: " & $idx2 & "    text: " & text

    return (currentDay, idx+1, text)

proc setResult(uid: string, row: int, oldText, res, activity: string) {.async.} =

    if res.len == 0:
        return

    let zrPref =
        if activity.toLowerAscii().find("race") >= 0: "ZR or "
        else: ""

    let newText = "bot: " & zrPref & res

    if newText == oldText:
        return
    
    let accessToken = get_store(uid, "access_token")
    let sheetId = get_store(uid, "sheet_id")

    let valueRange = "J" & $row

    let old = if oldText.len > 0: "\n  old: " & oldText else: ""

    let jReq = %*{
        "range": valueRange,
        "majorDimension": "ROWS",
        "values": [[ newText & old ]]
    }

    var headers = newHttpHeaders([("Content-Type", "application/json")])

    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" &
            valueRange & "?valueInputOption=RAW", accessToken,
            httpMethod = HttpPut, body = $jReq, extraHeaders = headers)

    let body = await res.body()
    let j = parseJson(body)
    if j.contains("updatedCells") and j["updatedCells"].getInt == 1:
        info "Spreadsheet updated"
    else:
        raise newException(MyError, "error during cell update")

proc getActivity(uid: string, dt: DateTime): Future[(string, Table[string, seq[
        float]])] {.async.} =
    let stravaAccessToken = get_store(uid, "strava_access_token")

    let res = await client.bearerRequest(stravaApi &
            "/athlete/activities?per_page=" & $stravaPageLimit, stravaAccessToken)
    let body = await res.body()
    let j = parseJson(body)

    let today_str = dt.format("YYYY-MM-dd")

    proc findToday(x: JsonNode): bool =
        x["start_date"].getStr("").startsWith(today_str.format())

    let foundActivities = j.getElems().filter(findToday)
    if foundActivities.len == 0:
        raise newException(MyError, "No records found in strava")

    let currentActivity = foundActivities[0]

    info "Strava activity name: ", currentActivity["name"].getStr
    let id = currentActivity["id"].getBiggestInt

    let utc_offset = currentActivity["utc_offset"].getFloat
    upd_store(uid, "utc_offset", $utc_offset)

    debug "get: " & stravaApi & "/activities/" & $id & "?include_all_efforts=false"

    let res2 = await client.bearerRequest(stravaApi & "/activities/" & $id &
            "?include_all_efforts=false", stravaAccessToken)
    let body2 = await res2.body()
    let j2 = parseJson(body2)

    let res3 = await client.bearerRequest(stravaApi & "/activities/" & $id &
            "/streams/time,watts?resolution=high&series_type=time", stravaAccessToken)
    let body3 = await res3.body()
    let j3 = parseJson(body3)

    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(
            y => y.getFloat))).toTable

    if t["time"].len != t["watts"].len:
        raise newException(MyError, "Streams are not equal len")

    var file = openAsync("2.json", fmWrite)
    await file.write(j3.pretty)
    file.close()

    return (j2["name"].getStr() & " " & $j2["distance"].getFloat() & "m " & j2[
            "type"].getStr(), t)

proc refresh_token(uid: string, prefix = ""): Future[string] {.async.} =
    info "Checking token for " & prefix
    let exp = get_store(uid, prefix & "expiration").parseInt
    if exp < getTime().toUnix():
        let refreshToken = get_store(uid, prefix & "refresh_token")
        info "Trying to refresh"
        let state = generateState()
        let res =
            if prefix == "":
                await client.refreshToken(accessTokenUrl, clientId,
                clientSecret, refreshToken, clientScope, useBasicAuth = false)
            elif prefix == "strava_":
                await client.refreshToken(stravaAccessTokenUrl, stravaClientId,
                stravaClientSecret, refreshToken, stravaClientScope, useBasicAuth = false)
            else:
                raise newException(ValueError, "invalid prefix")
        let body = await res.body()
        let j = parseJson(body)

        if j.contains("access_token") and j.contains("expires_in"):
            upd_store(uid, prefix & "access_token", j["access_token"].getStr)
            let exp = (getTime() + initDuration(seconds = j[
                    "expires_in"].getInt)).toUnix()
            upd_store(uid, prefix & "expiration", $exp)
        else:
            raise newException(MyError, "cannot refresh token for " & prefix)
    else:
        info "Using active token"

    return get_store(uid, prefix & "access_token")

proc process_all*(testRun: bool, daysOffset: int) {.async.} =
    var empty = true
    let today = now() - initDuration(days = daysOffset)
    for (uid, email) in get_uids():
        empty = false
        await process(testRun, today, uid, email)

    if empty:
        warn "No records found. Try to run with --reg flag for registration"

proc process(testRun: bool, today: DateTime, uid, email: string) {.async.} =
    let fmt = "yyyy-MM-dd"
    let test = if testRun:"testRun" else:""
    info fmt"Processing {uid} ({email}) for {today.format(fmt)} {test}"
    let access = await refresh_token(uid)
    let stravaAccess = await refresh_token(uid, "strava_")
    # let today = initDateTime(01, mApr, 2020, 0, 0, 0, utc())

    try:
        let (plan, row, text) = await getPlan(uid, today)
        let (activity, tw) = await getActivity(uid, today)

        let pattern = normalize_plan(plan)
        let (_, res) = pattern.process(tw["time"], tw["watts"])

        let resStr = res.normalize_result()
        info "Result: ", resStr
        if not testRun:
            await setResult(uid, row, text, resStr, activity)
    except MyError:
        warn getCurrentExceptionMsg()

    info "done"

proc http*() {.async.} =
    info fmt"Browser to the {redirectUri} for registration"
    await server.serve(Port(httpPort), http_handler)
