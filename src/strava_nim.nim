
import asynchttpserver, asyncdispatch
import tables
import sequtils
import strutils
import json
import times
import strformat
import algorithm
import asyncfile
import sugar

import analytic
import storage
import http_oauth

var server = newAsyncHttpServer()

    
proc main2() {.async.} =
    var file = openAsync("2.json", fmRead)
    let body3 = await file.readAll()
    file.close()
    let j3 = parseJson(body3)
    let t = j3.getElems().map(x => (x["type"].getStr, x["data"].getElems().map(y => y.getFloat))).toTable
    if t["time"].len != t["watts"].len:
        raise newException(ValueError, "Streams are not equal len")
    "1x15 (240) + 7x3 (310)".normalize_plan().process(t["time"], t["watts"])
    # "1x15 (240)".normalize_plan().process(t["time"], t["watts"])
    # "7x3 (240)".normalize_plan().process(t["time"], t["watts"])

when isMainModule:
    try:
        # waitFor server.serve(Port(8080), http_handler)
        waitFor main2()
    except:
        echo "Exception: " & getCurrentExceptionMsg()

