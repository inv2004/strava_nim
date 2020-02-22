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


import storage
import times
import analytic


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

let client = newAsyncHttpClient()

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
            let accessToken = j["access_token"].getStr()

            let profile = await email_test(accessToken)
            let uid = profile[0]
            # let email = profile[1]

            store(profile, accessToken)
            upd_store(uid, "refresh_token", j["refresh_token"].getStr)
            upd_store(uid, "sheet_id", params["sheet_id"])

            let res2 = await sheet_test(params["sheet_id"], accessToken)
            let msg = """
<HTML>Ok:<br/>""" & res2 & """
<p/>
<a href="/sauth?uid=""" & uid & """">Strava Auth</a>
</HTML>
"""
            await req.respond(Http200, msg, headers)
        else:
            await req.respond(Http200, "<HTML>Error. <a href=\"/\">Restart</a></HTML>", headers)
    elif req.url.path == "/sauth":
        let params = req.url.query.parseQuery()
        let state = generateState()
        let grantUrl = getAuthorizationCodeGrantUrl(
            stravaAuthorizeUrl,
            stravaClientId,
            redirectUri & "/scode?uid=" & params["uid"],
            state,
            @["activity:read_all"],
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
        let body =  await resp.body()
        let j = parseJson(body)
        # echo j.pretty
        if j.contains("access_token"):
            upd_store(uid, "strava_access_token", j["access_token"].getStr)

            let athlete = j["athlete"]
            let msg = """
<HTML>
Ok<br/>Hello """ & athlete["firstname"].getStr() & " " & athlete["lastname"].getStr() & """
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
        
        let plan = await getPlan(uid, today)
        let (activity, tw) = await getActivity(uid, today)

        let pattern = normalize_plan(plan)
        let res = pattern.process(tw["time"], tw["watts"])

        let msg = """
<HTML>
    <table border=3>
        <tr><td>Today:</td><td>""" & today.format("YYYY-MM-dd") & """</td></tr>
        <tr><td>Plan:</td><td>""" & plan & """</td></tr>
        <tr><td>Activity:</td><td>""" & activity & """</td></tr>
        <tr><td>Activity:</td><td>""" & $res & """</td></tr>
    </table>
</HTML>
"""
        await req.respond(Http200, msg, headers)
    else:
        await req.respond(Http404, "Not Found")

proc getPlan(uid: string, dt: DateTime): Future[string] {.async.} =
    let accessToken = get_store(uid, "access_token")
    let sheetId = get_store(uid, "sheet_id")

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

proc getActivity(uid: string, dt: DateTime): Future[(string, Table[string, seq[float]])] {.async.} =
    let stravaAccessToken = get_store(uid, "strava_access_token")

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
