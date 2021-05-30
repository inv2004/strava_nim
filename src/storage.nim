import flatdb
import json

var db = newFlatDb("testdb.db", false)
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
