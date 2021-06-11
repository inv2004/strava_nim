{.experimental: "codeReordering".}

import oauth2
import httpclient
import uri
import asyncdispatch
import asynchttpserver
from nativesockets import AF_INET, AF_INET6
import asyncfile
import json
import sequtils
import strutils
import tables
import sugar
import strformat
import logging
import algorithm
import math

import storage
import times
import analytic

const kmCol = 'F'
const mTimeCol = 'G'
const kCalCol = 'H'
const resultCol = 'I'

const valueInputType = "USER_ENTERED"

type
    MyError* = object of ValueError

var
    httpHost = "strava.tradesim.org"
    redirectUri = "https://" & httpHost

const
    listenAddr = "127.0.0.1"
    httpPort = 8080
    #clientId = "438197548914-kp6b5mu5543gdinspvt5tgj0s71q1vbv.apps.googleusercontent.com"
    clientId = "438197548914-rd4afdt82qk0hd9qntp8bg2cd1pprp5v.apps.googleusercontent.com"
    #clientSecret = "F3FV-r9obIVHG3gW6JvDP95m"
    clientSecret = "cGtgJ69WgFJejypLUzxCoTFA"
    clientScope = @["https://www.googleapis.com/auth/spreadsheets", "email"]
    authorizeUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    accessTokenUrl = "https://accounts.google.com/o/oauth2/token"
    sheetApi = "https://sheets.googleapis.com/v4/spreadsheets"
    userinfoApi = "https://www.googleapis.com/userinfo/v2/me"
    stravaClientId = "18057"
    stravaClientSecret = "05e15bf725a7c4ee80fcd6683c8bebd5a5811cef"
    stravaClientScope = @["activity:read_all"]
    stravaAuthorizeUrl = "http://www.strava.com/oauth/authorize"
    stravaAccessTokenUrl = "https://www.strava.com/oauth/token"
    stravaApi = "https://www.strava.com/api/v3"
    stravaPageLimit = 50
    reqTimeout = 5000
    # image = "https://i.postimg.cc/3Ryhbydt/3.png"
    image = "https://i.ibb.co/NNHnq96/3.png"

proc withTimeoutEx[T](fut: Future[T]): owned(Future[T]) {.async.} =
    let res = await fut.withTimeout(reqTimeout)
    if res:
        return fut.read()
    else:
        raise newException(IOError, "Request timeout")

var server = newAsyncHttpServer()

let client = newAsyncHttpClient()

proc email_test(accessToken: string): Future[(string, string)] {.async.} =
    let res = await client.bearerRequest(userinfoApi, accessToken).withTimeoutEx()
    let body = await res.body()

    let j = parseJson(body)

    return (j["id"].getStr, j["email"].getStr)

proc sheet_test(sheetId: string, accessToken: string): Future[string] {.async.} =
    let valueRange = "A1:E10"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" &
            valueRange & "?majorDimension=ROWS", accessToken).withTimeoutEx()
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

        let sheetId = ""

        let msg = """
<HTML><form action="/check_sheet">spreadsheet id:
    <input type="text" name="sheet_id" value="""" & sheetId &
                """" size="60"/><br>
    <input type="submit" value="check"/>
    <p/>
    How to find it:<br>
    <img src="""" & image & """" alt="id" border="0">
    <input type="hidden" name="code" value="""" & grantResponse.code & """"/>
</form></HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/check_sheet":
        let params = req.url.query.parseQuery()
        let code = decodeUrl(params["code"])

        let resp = await client.getAuthorizationCodeAccessToken(
            accessTokenUrl,
            code,
            clientId,
            clientSecret,
            redirectUri & "/gcode",
            useBasicAuth = false
        ).withTimeoutEx()
        let body = await resp.body()
        let j = parseJson(body)
        debug j

        if j.contains("error"):
            await req.respond(Http200, """
<HTML>There is an error from google OAuth.<br>
    <p/>
    Please try again <a href="/">Restart</a><br>
""", headers)
            return

        if not j.contains("access_token"): raise newException(MyError, "No access_token found from google")
        if not j.contains("expires_in"): raise newException(MyError, "No expires_in found from google")

        let accessToken = j["access_token"].getStr()

        let profile = await email_test(accessToken)
        let uid = profile[0]
            # let email = profile[1]

        if not j.contains("refresh_token"):
            try:
                let rt = get_store(uid, "refresh_token")
                await req.respond(Http200, """
<HTML>No refresh_token found in google response.<br>
    But we have stored one. Looks like you are already registered.
    <p/>
    If you want, please continue to strava authorization <a href="/strava?uid=""" & uid & """">Strava Auth</a><br>
""", headers)
                return
            except:
                await req.respond(Http200, """
<HTML>No refresh_token found in google response<br>
    Please remove strava-nim permissions from <a href="https://myaccount.google.com/u/0/permissions">https://myaccount.google.com/u/0/permissions</a><br>
    and then try again: <a href="/">Restart</a></HTML>
""", headers)
                return

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
<a href="/strava?uid=""" & uid & """">Strava Auth</a>
</HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/strava":
        let params = req.url.query.parseQuery()
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            stravaAuthorizeUrl,
            stravaClientId,
            redirectUri & "/sauth?uid=" & params["uid"],
            state,
            stravaClientScope,
            accessType = "offline"
        )
        headers["Location"] = grantUrl
        await req.respond(Http301, "", headers)
    elif req.url.path == "/sauth":
        let params = req.url.query.parseQuery()
        let uid = params["uid"]
        # echo $params
        let resp = await client.getAuthorizationCodeAccessToken(
            stravaAccessTokenUrl,
            params["code"],
            stravaClientId,
            stravaClientSecret,
            redirectUri & "/sauth?uid=" & params["uid"],
            useBasicAuth = false
        ).withTimeoutEx()
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
To complete registration <a href="/process?uid=""" & params["uid"] & """">process The Day</a> to check that it works (no data will be updated)
</HTML>
"""
            await req.respond(Http200, msg, headers)
        else:
            await req.respond(Http200, "<HTML>Error. <a href=\"/\">Restart</a></HTML>", headers)
    elif req.url.path == "/process":
        let params = req.url.query.parseQuery()
        let uid = params["uid"]

        let today = now()  ## TODO: duplicate of process function

        try:
            let (plan, _, _) = await getPlan(uid, today)
            let activities = await getActivities(uid, today, 3)

            let res =
                try:
                    await getBikeResults(uid, plan, activities)
                except MyError:
                    getCurrentExceptionMsg().split("\n")[0]

            upd_store(uid, "active", "true")

            let msg = """
    <HTML>
        Example:
        <table border=3>
            <tr><td>Today:</td><td>""" & today.format("YYYY-MM-dd") &
                    """</td></tr>
            <tr><td>Plan:</td><td>""" & plan &
                    """</td></tr>
            <tr><td>Activity:</td><td>""" & plan &
                    """</td></tr>
            <tr><td>Result:</td><td>""" & $res & """</td></tr>
        </table>
        Your registration is complete and will be processes automatically every hour
    </HTML>
    """
            await req.respond(Http200, msg, headers)
        except MyError:
            let msg = getCurrentExceptionMsg()
            warn msg
            await req.respond(Http200, "Exception: " & msg, headers)

    else:
        await req.respond(Http404, "Not Found")

proc getPlan(uid: string, dt: DateTime): Future[(string, int, seq[string])] {.async.} =
    debug "Requesting current plan"
    let accessToken = get_store(uid, "access_token")
    let sheetId = get_store(uid, "sheet_id")

    let valueRange = "A:J"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" &
            valueRange & "?majorDimension=ROWS", accessToken).withTimeoutEx()
            # valueRange & "?majorDimension=ROWS&valueRenderOption=FORMULA", accessToken)
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

    var old = newSeq[string]()

    old.add elems[idx]{5}.getStr()
    old.add elems[idx]{6}.getStr()
    old.add elems[idx]{7}.getStr()
    old.add elems[idx]{8}.getStr()

    let idx2 = idx + 1

    info "Current plan: " & currentDay & "    row: " & $idx2 & "    old: " & old.join()

    return (currentDay, idx+1, old)

proc getOldText(txt: string): string =

    var lines = txt.split("\n")
    if lines.len > 0 and lines[0].startsWith("bot: "):
        lines.delete(0)

    result = lines.join("\n")

    if result.len > 0:
        if not result.startsWith("  old: "):
            result = "  old: " & result
        result = "\n" & result

proc setResultValue(uid: string, row: int, col: char, oldText, res: string) {.async.} =
    if res.len == 0:
        return

    let newText = if col == resultCol: "bot: " & res else: res

    if newText == oldText:
        return
    
    let accessToken = get_store(uid, "access_token")
    let sheetId = get_store(uid, "sheet_id")

    let valueRange = col & $row

    let old =
        if oldText.len > 0 and col == resultCol: getOldText(oldText)
        else: ""

    let jReq = %*{
        "range": valueRange,
        "majorDimension": "ROWS",
        "values": [[ newText & old ]]
    }

    var headers = newHttpHeaders([("Content-Type", "application/json")])

    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" & valueRange & "?valueInputOption=" & valueInputType
            , accessToken,
            httpMethod = HttpPut, body = $jReq, extraHeaders = headers).withTimeoutEx()

    let body = await res.body()

    let j = parseJson(body)
    if j.contains("updatedCells") and j["updatedCells"].getInt == 1:
        info "Spreadsheet updated for " & col & $row
    else:
        raise newException(MyError, "error during cell update")

proc getKm(activities: seq[JsonNode]): string =
    let a =  activities.mapIt(it{"distance"}.getFloat()).mapIt(it / 1000).mapIt(it.int).reversed()
    if a.len > 0:
        if a.len == 1 and a.sum() == 0:
            discard
        else:
            result = "=" & a.join("+")

proc getDetailedCalories(uid: string, id: BiggestInt): Future[int] {.async.} =
    let stravaAccessToken = get_store(uid, "strava_access_token")
    let res = await client.bearerRequest(stravaApi & "/activities/" & $id, stravaAccessToken).withTimeoutEx()
    let body = await res.body()
    let j = parseJson(body)
    return j["calories"].getFloat().int

proc getKilojoules(uid: string, activities: seq[JsonNode]): Future[string] {.async.} =
    var kjs = newSeq[int]()
    for a in activities:
        if a["type"].getStr() == "Run":
            kjs.add await getDetailedCalories(uid, a["id"].getBiggestInt)
        else:
            kjs.add a{"kilojoules"}.getFloat().int

    if kjs.len > 0:
        if kjs.sum() == 0:
            return ""
        else:
            return "=" & kjs.reversed().join("+")

proc getMovingTime(activities: seq[JsonNode]): string =
    let minutes = activities.mapIt(it{"moving_time"}.getFloat()).sum() / 60
    if minutes == 0:
        return ""
    let dp = initDuration(minutes = minutes.int64).toParts()
    return fmt"{dp[Hours]}:{dp[Minutes]:02d}"


proc getActivities(uid: string, dt: DateTime, stravaPagesMax: int): Future[seq[JsonNode]] {.async.} =
    debug "Requesting strava activities"

    let stravaAccessToken = get_store(uid, "strava_access_token")
    let today_str = dt.format("YYYY-MM-dd")

    for page in 1..stravaPagesMax:
        let res = await client.bearerRequest(stravaApi &
                "/athlete/activities?page=" & $page & "&per_page=" & $stravaPageLimit, stravaAccessToken).withTimeoutEx()
        let body = await res.body()
        let j = parseJson(body)

        let elems = j.getElems()

        if elems.len > 0:
            let lastDateOnPage = elems[^1]["start_date"].getStr(newString(10))[0..9]
            if today_str < lastDateOnPage:
                info "The last date on strava's page is ", lastDateOnPage, " trying next page"
                continue

        let foundDaysActivities = elems.filterIt(it["start_date"].getStr("").startsWith(today_str))

        let j1: JsonNode = %foundDaysActivities
        var file = openAsync("1.json", fmWrite)
        await file.write(j1.pretty)
        
        return foundDaysActivities

proc getBikeActivities(uid: string, activities: seq[JsonNode]): Future[seq[(string, seq[float], seq[float])]] {.async.} =
    let foundActivities = activities.filterIt(it["type"].getStr().endsWith("Ride"))

    if foundActivities.len == 0:
        raise newException(MyError, "No Ride records found in strava")

    for currentActivity in foundActivities:

        info "Strava activity name: ", currentActivity["name"].getStr
        let id = currentActivity["id"].getBiggestInt

        let utc_offset = currentActivity["utc_offset"].getFloat
        upd_store(uid, "utc_offset", $utc_offset)

        debug "get: " & stravaApi & "/activities/" & $id & "?include_all_efforts=false"

        let stravaAccessToken = get_store(uid, "strava_access_token")

        let res2 = await client.bearerRequest(stravaApi & "/activities/" & $id &
                "?include_all_efforts=false", stravaAccessToken).withTimeoutEx()
        let body2 = await res2.body()
        let j2 = parseJson(body2)

        var file = openAsync("2.json", fmWrite)
        await file.write(j2.pretty)
        file.close()

        let actName = j2["name"].getStr() & " " & $j2["distance"].getFloat() & "m " & j2["type"].getStr()

        if j2["device_watts"].getBool():
            debug "get: " & stravaApi & "/activities/" & $id & "/streams/time,watts?resolution=high&series_type=time"

            let res3 = await client.bearerRequest(stravaApi & "/activities/" & $id &
                    "/streams/time,watts?resolution=high&series_type=time", stravaAccessToken).withTimeoutEx()
            let body3 = await res3.body()
            let j3 = parseJson(body3)

            file = openAsync("3.json", fmWrite)
            await file.write(j3.pretty)
            file.close()

            let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(
                    y => y.getFloat))).toTable

            if t["time"].len != t["watts"].len:
                raise newException(MyError, "Streams are not equal len")

            result.add @[(actName, t["time"], t["watts"])]
        else:
            result.add @[(actName, newSeq[float](), newSeq[float]())]            

proc refresh_token(uid: string, prefix = ""): Future[string] {.async.} =
    debug "Checking token for " & prefix
    let exp = get_store(uid, prefix & "expiration").parseInt
    if exp < getTime().toUnix():
        let refreshToken = get_store(uid, prefix & "refresh_token")
        info "Trying to refresh token for " & prefix
        let state = generateState()
        let res =
            if prefix == "":
                await client.refreshToken(accessTokenUrl, clientId,
                clientSecret, refreshToken, clientScope, useBasicAuth = false).withTimeoutEx()
            elif prefix == "strava_":
                await client.refreshToken(stravaAccessTokenUrl, stravaClientId,
                stravaClientSecret, refreshToken, stravaClientScope, useBasicAuth = false).withTimeoutEx()
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
        debug "Using active token"

    return get_store(uid, prefix & "access_token")

proc mergeRegistered() =
    loadDB("reg")
    var newUsers: seq[JsonNode]
    for v in dbGetDeleteValues():
        newUsers.add v
    loadDB("active")
    merge(newUsers)

proc stravaOffset(uid: string): int =
    try:
        result = get_store(uid, "utc_offset").parseFloat().int
    except ValueError:
        discard

proc process_all*(testRun: bool, daysOffset, stravaPagesMax: int) {.async.} =
    mergeRegistered()

    var empty = true

    let today = now() - initDuration(days = daysOffset)
    for (uid, email) in get_uids():
        empty = false

        try:
            await process(testRun, today, uid, email, stravaPagesMax)
        except:
            error "Error while processing ", email, ": ", getCurrentExceptionMsg()

    if empty:
        warn "No records found. Try to run with --reg flag for registration"

proc getBikeResults(uid: string, plan: string, activities: seq[JsonNode]): Future[string] {.async.} =
    let tw = await getBikeActivities(uid, activities)

    let pattern = normalize_plan(plan)
    let (_, res) = pattern.process(tw)

    let zrPref =
        if tw.anyIt(it[0].toLowerAscii().find("race") >= 0): "ZR or "
        else: ""

    result = zrPref & $res

proc process(testRun: bool, today: DateTime, uid, email: string, stravaPagesMax: int) {.async.} =
    let fmt = "yyyy-MM-dd"
    let test = if testRun:"testRun" else:""

    let stravaOff = stravaOffset(uid)
    let today = today + stravaOff.seconds

    info fmt"Processing {uid} ({email}) for {today.format(fmt)} ({stravaOff}) {test}"
    let access = await refresh_token(uid)
    let stravaAccess = await refresh_token(uid, "strava_")
    # let today = initDateTime(01, mApr, 2020, 0, 0, 0, utc())

    try:
        let (plan, row, old) = await getPlan(uid, today)
        let activities = await getActivities(uid, today, stravaPagesMax)

        let km = getKm(activities)
        info "    km: ", km

        let time = getMovingTime(activities)
        info "  Time: ", time

        let kcal = await getKilojoules(uid, activities)
        info "  KCal: ", kcal

        if not testRun:
            await setResultValue(uid, row, kmCol, old[0], km)
            await setResultValue(uid, row, mTimeCol, old[1], time)
            await setResultValue(uid, row, kCalCol, old[2], kcal)

        let res = await getBikeResults(uid, plan, activities)

        info "Result: ", res

        if not testRun:
            await setResultValue(uid, row, resultCol, old[3], res)

    except MyError:
        warn getCurrentExceptionMsg()

    info "done"

proc http*(local: bool) {.async.} =
    if local:
        httpHost = "localhost"
        redirectUri = "http://" & httpHost & ":" & $httpPort
        # listenAddr = "0.0.0.0"

    info fmt"Browser to the {redirectUri} for registration"
    loadDB("reg")
    await server.serve(Port(httpPort), http_handler, address = listenAddr, domain = AF_INET6)
