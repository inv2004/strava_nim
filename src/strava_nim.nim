import asyncdispatch
import tables
import sequtils
import json
import strutils
import asyncfile
import sugar
import logging
import parseopt
import re

import analytic
import http_oauth

let fmtStr = "[$date $time] - $levelname: "
var consoleLog = newConsoleLogger(fmtStr = fmtStr)
var rollingLog = newRollingFileLogger("strava_nim.log", mode = fmAppend, fmtStr = fmtStr)

addHandler(consoleLog)
addHandler(rollingLog)

import stats

proc main2() {.async.} =
    var file = openAsync("/mnt/c/Users/u/Downloads/3.json", fmRead)
    let body3 = await file.readAll()
    file.close()
    let j3 = parseJson(body3)
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(
            y => y.getFloat))).toTable
    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")
    echo "1x15(255) + 6x5 (255)".normalize_plan().process(@[("abc", t["time"], t["watts"])])
    # echo "6x5 (255)".normalize_plan().process(@[("abc", t["time"], t["watts"])])
    echo t["watts"][31..930].mean()

proc print_help() =
    echo """
    strava_nim                  # to process all users from current database to current data
    strava_nim --Xd [pattern]   # the same like previous with X days back. pattern - optional
    strava_nim --test           # the same like previous without storing results
    strava_nim --reg            # to start in http mode for registration
"""

proc main() =
    try:
        var http = false
        var local = false
        var pattern = ""
        var daysOffset = 0
        var stravaPagesMax = 3
        var testRun = false

        for kind, key, val in getopt():
            if key == "h" or key == "help":
                print_help()
                system.quit()
            elif key == "reg":
                http = true
            elif key == "local":
                local = true
            elif key == "p":
                pattern = val
            elif key.match(re"^\d+d$"):
                daysOffset = parseInt(key[0..^2])
            elif key.match(re"^\d+p$"):
                stravaPagesMax = parseInt(key[0..^2])
            elif key == "test":
                testRun = true
            
        if http:
            waitFor http(local)
        else:
            waitFor process_all(testRun, daysOffset, stravaPagesMax, pattern)
    except:
        error "Exception: " & getCurrentExceptionMsg()

when isMainModule:
    main()
