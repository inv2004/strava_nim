import oauth2
import httpclient
import uri

import asyncdispatch
import asynchttpserver
import asyncfile
import json

let client = newAsyncHttpClient()

proc google() =
    var headers = newHttpHeaders([("Cache-Control", "no-cache")])
    headers["Content-Type"] = "text/html; charset=utf-8"

    let state = generateState()
    let grantUrl = getAuthorizationCodeGrantUrl(
        authorizeUrl,
        clientId,
        redirectUri & "/gcode",
        state,
        @["https://www.googleapis.com/auth/spreadsheets", "email"],
        accessType = "offline"
    )
    headers["Location"] = grantUrl
    await req.respond(Http301, "", headers)

