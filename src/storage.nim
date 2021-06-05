import flatdb
import json
import logging

var db: FlatDb

proc loadDB*(name: string) =
  db = newFlatDb(name & ".db", false)
  discard db.load()

# TODO: refactoring
proc store*(profile: (string, string), accessToken: string) =
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
proc upd_store*(id: string, key: string, value: string) =
  let entry = db.queryOne equal("id", id)
  let db_id = entry["_id"].getStr
  db[db_id][key] = newJString(value)
  db.flush()

# TODO: refactoring
proc get_store*(id: string, key: string): string =
  let entry = db.queryOne equal("id", id)
  entry[key].getStr

iterator get_uids*(): (string, string) =
  for x in db:
    yield (x["id"].getStr, x["email"].getStr)

iterator dbValues*(): JsonNode =
  for x in db:
    if x["active"].getStr() == "true":
      delete(x, "_id")
      yield x

proc merge*(vals: seq[JsonNode]) =
  for v in vals:
    if v["active"].getStr() == "true":
      let email = v["email"].getStr()
      if email.len == 0:
        continue
      info "Upsert into storage: ", email
      db.upsert(v, equal("email", email))
    
proc dbDrop*() =
  db.drop()

