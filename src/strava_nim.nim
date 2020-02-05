{.experimental: "codeReordering".}

import oauth2
import asynchttpserver, asyncdispatch
import tables
import sequtils
import strutils
import httpclient
import uri
import json
import times
import sugar
import asyncfile
import strformat
import algorithm
import re
import flatdb
# import lmdb

type
    Interval = tuple
        avg: float
        start: int
        stop: int

    Pattern = tuple
        repeat: int
        duration: float

func duration(a: Interval): float =
    (a.stop - a.start + 1).float

proc `$`(a: Interval): string =
    let tstr = fromUnix(a.start).format("mm:ss")
    let dstr = fromUnix(a.duration.int).format("mm:ss")
    fmt"(avg: {a.avg}, start: {tstr}, duration: {dstr})"

const
    clientId = "438197548914-kp6b5mu5543gdinspvt5tgj0s71q1vbv.apps.googleusercontent.com"
    clientSecret = "F3FV-r9obIVHG3gW6JvDP95m"
    authorizeUrl = "https://accounts.google.com/o/oauth2/v2/auth"
    accessTokenUrl = "https://accounts.google.com/o/oauth2/token"
    redirectUri = "http://localhost:8080"
    sheetApi = "https://sheets.googleapis.com/v4/spreadsheets"
    userinfoApi = "https://www.googleapis.com/userinfo/v2/me"
    stravaClientId = "18057"
    stravaClientSecret = "05e15bf725a7c4ee80fcd6683c8bebd5a5811cef"
    stravaAuthorizeUrl = "http://www.strava.com/oauth/authorize"
    stravaAccessTokenUrl = "https://www.strava.com/oauth/token"
    stravaApi = "https://www.strava.com/api/v3"

var accessToken = ""
var stravaAccessToken = ""
var sheetId = ""

var server = newAsyncHttpServer()
let client = newAsyncHttpClient()

var db = newFlatDb("testdb.db", false)
discard db.load()

proc store(profile: (string, string), accessToken: string) = # TODO: refactoring
    let id = profile[0]
    let email = profile[1]

    discard db.append(%* {"id": id, "email": email, "access_token": accessToken})
    db.flush()

proc upd_store(id: string, refreshToken: string) = # TODO: refactoring
    let entry = db.queryOne equal("id", id)
    let db_id = entry["_id"].getStr
    db[db_id]["refresh_token"] = % refreshToken
    db.flush()

proc email_test(accessToken: string): Future[(string, string)] {.async.} =
    let res = await client.bearerRequest(userinfoApi, accessToken)
    let body = await res.body()

    let j = parseJson(body)

    return (j["id"].getStr, j["email"].getStr)


proc sheet_test(sheetId: string, accessToken: string): Future[string] {.async.} =
    let valueRange = "A1:E10"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" & valueRange & "?majorDimension=ROWS", accessToken)
    let body = await res.body()
    let j = parseJson(body)

    proc to_html(j: JsonNode): string =
        j.getElems().map(proc (x: JsonNode): string = "<td>"&x.getStr()&"</td>").join()    

    return "<table border=2><tr>" & j["values"].getElems().map(to_html).join("</tr><tr>") & "</tr></table>"

proc parseQuery(query: string): TableRef[string, string] =
    let responses = query.split("&")
    result = newTable[string, string]()
    for response in responses:
        let fd = response.find("=")
        result[response[0..fd-1]] = response[fd+1..len(response)-1].decodeUrl()

proc handler(req: Request) {.async, gcsafe.} =
    var headers = newHttpHeaders([("Cache-Control", "no-cache")])
    headers["Content-Type"] = "text/html; charset=utf-8"

    if req.url.path == "/":
        let msg = """
<HTML>Click here to start start authorisation <a href="/gauth">Google Auth</a></HTML>
"""
        await req.respond(Http200, msg, headers)
    elif req.url.path == "/gauth":
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            authorizeUrl,
            clientId,
            redirectUri & "/gcode",
            state,
            @["https://www.googleapis.com/auth/spreadsheets",
              "email"],
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
    <input type="text" name="sheet_id" value="""" & sheetId & """" size="60"/>
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
        let body =  await resp.body()
        let j = parseJson(body)
        echo j
        if j.contains("access_token"):
            accessToken = j["access_token"].getStr()

            let profile = await email_test(accessToken)

            store(profile, accessToken)
            upd_store(profile[0], j["refresh_token"].getStr)

            sheetId = params["sheet_id"]
            let res2 = await sheet_test(params["sheet_id"], accessToken)
            let msg = """
<HTML>Ok:<br/>""" & res2 & """
<p/>
<a href="/sauth">Strava Auth</a>
</HTML>
"""
            await req.respond(Http200, msg, headers)
        else:
            await req.respond(Http200, "<HTML>Error. <a href=\"/\">Restart</a></HTML>", headers)
    elif req.url.path == "/sauth":
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            stravaAuthorizeUrl,
            stravaClientId,
            redirectUri & "/scode",
            state,
            @["activity:read_all"],
            accessType = "offline"
        )
        headers["Location"] = grantUrl
        await req.respond(Http301, "", headers)
    elif req.url.path == "/scode":
        let params = req.url.query.parseQuery()
        # echo $params
        let resp = await client.getAuthorizationCodeAccessToken(
            stravaAccessTokenUrl,
            params["code"],
            stravaClientId,
            stravaClientSecret,
            redirectUri & "/gcode",
            useBasicAuth = false
        )
        let body =  await resp.body()
        let j = parseJson(body)
        # echo j.pretty
        if j.contains("access_token"):
            stravaAccessToken = j["access_token"].getStr()
            let athlete = j["athlete"]
            let msg = """
<HTML>
Ok<br/>Hello """ & athlete["firstname"].getStr() & " " & athlete["lastname"].getStr() & """
<p/>
<a href="/process">Process The Day</a>
</HTML>
"""
            await req.respond(Http200, msg, headers)
        else:
            await req.respond(Http200, "<HTML>Error. <a href=\"/\">Restart</a></HTML>", headers)
    elif req.url.path == "/process":
        # let today = now() - initDuration(days = 3)
        let today = initDateTime(30, mJan, 2020, 0, 0, 0, utc())
        
        let plan = await getPlan(sheetId, today, accessToken)
        let (activity, tw) = await getActivity(today, stravaAccessToken)

        let pattern = normalize_plan(plan)
        pattern.process(tw["time"], tw["watts"])

        let msg = """
<HTML>
    <table border=3>
        <tr><td>Today:</td><td>""" & today.format("YYYY-MM-dd") & """</td></tr>
        <tr><td>Plan:</td><td>""" & plan & """</td></tr>
        <tr><td>Activity:</td><td>""" & activity & """</td></tr>
    </table>
</HTML>
"""
        await req.respond(Http200, msg, headers)
    else:
        await req.respond(Http404, "Not Found")

func normalize_plan(plan: string): seq[Pattern] =
    for x in plan.findAll(re"\d+x\d+"):
        let vals = x.split('x')
        let pattern: Pattern = (vals[0].parseInt, (60 * vals[1].parseInt).float)
        result.add(pattern)

proc getPlan(sheetId: string, dt: DateTime, stravaAccessToken: string): Future[string] {.async.} =
    let valueRange = "A:E"
    let res = await client.bearerRequest(sheetApi & "/" & sheetId & "/values/" & valueRange & "?majorDimension=ROWS", accessToken)
    let body = await res.body()
    let j = parseJson(body)

    let today_str = dt.format("M/d/YYYY")

    proc checkFirst(x: JsonNode): bool =
        let row = x.getElems()
        if row.len > 0:
            row[0].getStr("") == today_str
        else:
            false
    
    let foundDates = j["values"].getElems().filter(checkFirst)
    if foundDates.len == 0:
        raise newException(ValueError, "No records found in sheet")
    
    let currentDay = foundDates[0][4]

    return $currentDay

proc getActivity(dt: DateTime, stravaAccessToken: string): Future[(string, Table[string, seq[float]])] {.async.} =
    let res = await client.bearerRequest(stravaApi & "/athlete/activities?per_page=10", stravaAccessToken)
    let body = await res.body()
    let j = parseJson(body)

    let today_str = dt.format("YYYY-MM-dd")

    proc findToday(x: JsonNode): bool =
        x["start_date"].getStr("").startsWith(today_str.format())

    let foundActivities = j.getElems().filter(findToday)
    if foundActivities.len == 0:
        raise newException(ValueError, "No records found in strava")

    let currentActivity = foundActivities[0]

    echo "Current activity: ", currentActivity["name"]
    let id = currentActivity["id"].getBiggestInt

    echo "get: " & stravaApi & "/activities/" & $id & "?include_all_efforts=false"

    let res2 = await client.bearerRequest(stravaApi & "/activities/" & $id & "?include_all_efforts=false", stravaAccessToken)
    let body2 = await res2.body()
    let j2 = parseJson(body2)

    let res3 = await client.bearerRequest(stravaApi & "/activities/" & $id & "/streams/time,watts?resolution=high&series_type=time", stravaAccessToken)
    let body3 = await res3.body()
    let j3 = parseJson(body3)
    
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(y => y.getFloat))).toTable

    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")

    var file = openAsync("2.json", fmWrite)
    await file.write(j3.pretty)
    file.close()
    
    return (j2["name"].getStr() & " " & $j2["distance"].getFloat() & "m " & j2["type"].getStr(), t)

proc `$`(d: Duration): string =
    let d = d.toParts()
    fmt"{d[Hours]}:{d[Minutes]:02}:{d[Seconds]:02}"

proc process_best(pattern: seq[Pattern], time: seq[float], watts: seq[float]): seq[Interval] =
    for (repeat, ws) in pattern:
        var acc = 0.0
        var i = 0
        for ii, (tt, x) in time.zip(watts):
            let t = tt.int
            while time[i].int <= t-ws.int:
                acc -= watts[i]
                i += 1
            acc += x
            if t+1 >= ws.int:
                let interval: Interval = (acc / ws, time[i].int, t)
                result.add(interval)

    func cmp2(a, b: Interval): int =
        result = cmp(a.avg, b.avg)
        if result == 0:
            result = cmp(a.start, b.start)
            if result == 0:
                result = cmp(a.stop, b.stop)

    result.sort(cmp2, Ascending)

proc process_select(pattern: seq[Pattern], best: seq[Interval]): seq[Interval] =
    var best = best
    func overlap(a,b: Interval): bool =
        if a.start <= b.start and a.stop > b.start:
            return true
        if b.start <= a.start and b.stop > a.start:
            return true
        return false

    # var ps = pattern
    # while best.len > 0 and ps.len > 0:
    #     let x = best.pop()
    #     for p in ps.mitems:
    #         if x.duration >= p.duration:
    #             block checkBlock:
    #                 for y in result:
    #                     if overlap(x, y):
    #                         # echo "overlap ", x, y
    #                         break checkBlock
    #                 result.add(x)
    #                 p[0] -= 1
    #     ps.keepItIf(it[0] > 0)
    #     echo $ps

    for (p, res) in pattern.zip(best):
        var repeat = p.repeat
        let ws = p.duration
        while best.len > 0 and repeat > 0:
            let x = best.pop()
            if x.duration >= ws:
                block checkBlock:
                    for y in result:
                        if overlap(x, y):
                            # echo "overlap ", x, y
                            break checkBlock
                    result.add(x)
                    repeat -= 1

    func cmp3(a, b: Interval): int =
        result = cmp(a.start, b.start)
        if result == 0:
            result = cmp(a.avg, b.avg)
            if result == 0:
                result = cmp(a.stop, b.stop)

    result.sort(cmp3, Ascending)

proc process(pattern: seq[Pattern], time: seq[float], watts: seq[float]) =
    echo "processing ", pattern

    let best = pattern.process_best(time, watts)
    let found = pattern.process_select(best) 

    for x in found:
        echo x
    
proc main2() {.async.} =
    var file = openAsync("2.json", fmRead)
    let body3 = await file.readAll()
    file.close()
    let j3 = parseJson(body3)
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(y => y.getFloat))).toTable
    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")
    # "1x15 (240) + 7x3 (310)".normalize_plan().process(t["time"], t["watts"])
    "7x3 (240)".normalize_plan().process(t["time"], t["watts"])

proc test() {.async.} =
    let pattern = @[(1,2.0), (3,3.0)]

    let t = @[0,   1,  2,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 30, 20, 10, 5].map(x => x.float)
    pattern.process(t, w)
    echo ""
    let t2 = @[0,   1,  3,  4, 5].map(x => x.float)
    let w2 = @[10, 20, 20, 10, 5].map(x => x.float)
    pattern.process(t2, w2)

when isMainModule:
    try:
        waitFor server.serve(Port(8080), handler)
    except:
        echo "Exception: " & getCurrentExceptionMsg()

