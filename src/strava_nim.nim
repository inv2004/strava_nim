
import asyncdispatch
import tables
import sequtils
# import strutils
import json
import times
import strformat
import algorithm
import asyncfile
import sugar
import os
import logging

import analytic
import storage
import http_oauth

let fmtStr = "[$date $time] - $levelname: "
var consoleLog = newConsoleLogger(fmtStr = fmtStr)
var rollingLog = newRollingFileLogger("strava_nim.log", fmtStr = fmtStr)

addHandler(consoleLog)
addHandler(rollingLog)

proc main2() {.async.} =
    var file = openAsync("2.json", fmRead)
    let body3 = await file.readAll()
    file.close()
    let j3 = parseJson(body3)
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(y => y.getFloat))).toTable
    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")
    echo "1x15 (240) + 7x3 (310)".normalize_plan().process(t["time"], t["watts"])

when isMainModule:
    try:
        let reg = if os.paramCount() >= 1 and os.paramStr(1) == "--reg": true else: false

        if reg:
            waitFor http()
        else:
            waitFor process_all()
    except:
        echo "Exception: " & getCurrentExceptionMsg()

