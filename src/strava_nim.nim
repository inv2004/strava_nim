
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
    # "1x15 (240) + 7x3 (310)".normalize_plan().process(t["time"], t["watts"])
    "7x3 (240)".normalize_plan().process(t["time"], t["watts"])

proc test() {.async.} =
    let pattern = @[(1,2.0), (3,3.0)]

    let t = @[0,   1,  2,  3,  4, 5].map(x => x.float)
    let w = @[10, 20, 30, 20, 10, 5].map(x => x.float)
    pattern.process(t, w)

    echo ()
    
    let t2 = @[0,   1,  3,  4, 5].map(x => x.float)
    let w2 = @[10, 20, 20, 10, 5].map(x => x.float)
    pattern.process(t2, w2)

when isMainModule:
    try:
        waitFor server.serve(Port(8080), http_handler)
    except:
        echo "Exception: " & getCurrentExceptionMsg()

