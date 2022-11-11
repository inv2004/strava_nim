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
var rollingLog = newRollingFileLogger("strava_nim.log", mode = fmAppend,
        fmtStr = fmtStr)

addHandler(consoleLog)
addHandler(rollingLog)

proc print_help() =
  echo """
    strava_nim                  # to process all users from current database to current data
    strava_nim --Xd             # the same like previous with X days back
    strava_nim --Xp             # strava max pages
    strava_nim --test           # the same like previous without storing results
    strava_nim --reg            # to start in http mode for registration
    strava_nim --p=pattern      # process user with specific email pattern only
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
