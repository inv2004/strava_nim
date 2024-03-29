# Package

version       = "0.1.0"
author        = "Alexander Epifanov"
description   = "strava api"
license       = "MIT"
srcDir        = "src"
bin           = @["strava_nim"]



# Dependencies

requires "nim >= 1.0.4"
requires "oauth >= 0.8"
# requires "lmdb >= 0.1.2"
requires "flatdb >= 0.2.4"
requires "asciigraph >= 0.1.2"

task static, "static":
  exec "nim musl -d:pcre -d:openssl --mm:refc --threads:off src/strava_nim.nim"
