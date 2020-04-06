
import asyncdispatch
import tables
import sequtils
import json
import times
import strformat
import strutils
import algorithm
import asyncfile
import sugar
import os
import logging
import parseopt
import re

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
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(
            y => y.getFloat))).toTable
    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")
    echo "1x15 (240) + 7x3 (310)".normalize_plan().process(t["time"], t["watts"])

when isMainModule:
    try:
        var http = false
        var daysOffset = 0
        var testRun = false

        for kind, key, val in getopt():
            echo kind, " - ", key, " - ", val
            if key == "reg":
                http = true
            elif key.match(re"^\d+d$"):
                daysOffset = parseInt(key[0..^2])
            elif key == "test":
                testRun = true
            
        if http:
            waitFor http()
        else:
            waitFor process_all(testRun, daysOffset)
    except:
        error "Exception: " & getCurrentExceptionMsg()

