import flatdb
import json
import logging
import locks

var dbLock: Lock
var db {.guard: dbLock.}: FlatDb

initLock(dbLock)

proc loadDB*(name: string) =
  {.locks: [dbLock].}:
    db = newFlatDb(name & ".db", false)
    discard db.load()

# TODO: refactoring
proc store*(profile: (string, string), accessToken: string) =
  {.locks: [dbLock],gcsafe.}:
    let id = profile[0]
    let email = profile[1]
    let entry = db.queryOne equal("id", id)

    if not isNil entry:
      let db_id = entry["_id"].getStr
      db.delete db_id

    discard db.append( %* {"id": id, "email": email,
                            "access_token": accessToken})
    db.flush()

# TODO: refactoring
proc upd_store*(id: string, key: string, value: string) {.gcsafe.} =
  {.locks: [dbLock],gcsafe.}:
    let entry = db.queryOne equal("id", id)
    let db_id = entry["_id"].getStr
    db[db_id][key] = newJString(value)
    db.flush()

# TODO: refactoring
proc get_store*(id: string, key: string): string =
  {.locks: [dbLock],gcsafe.}:
    let entry = db.queryOne equal("id", id)
    entry[key].getStr

iterator get_uids*(): (string, string) =
  var res = newSeq[(string, string)]()
  {.locks: [dbLock],gcsafe.}:
    for x in db:
      res.add (x["id"].getStr, x["email"].getStr)
  for x in res:
    yield x

iterator dbGetDeleteValues*(): JsonNode =
  var res = newSeq[JsonNode]()
  {.locks: [dbLock].}:
    for x in db:
      if x["active"].getStr() == "true":
        let email = x["email"].getStr()
        if email.len == 0:
          continue
        delete(x, "_id")
        db.delete equal("email", email)
        res.add x
  for x in res:
    yield x

proc merge*(vals: seq[JsonNode]) =
  {.locks: [dbLock].}:
    for v in vals:
      let email = v["email"].getStr()
      info "Upsert into storage: ", email
      db.upsert(v, equal("email", email))
