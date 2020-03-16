import flatdb
import json

var db = newFlatDb("testdb.db", false)
discard db.load()

proc store*(profile: (string, string), accessToken: string) = # TODO: refactoring
    let id = profile[0]
    let email = profile[1]
    let entry = db.queryOne equal("id", id)

    if not isNil entry:
        let db_id = entry["_id"].getStr
        db.delete db_id

    discard db.append(%* {"id": id, "email": email, "access_token": accessToken})
    db.flush()

proc upd_store*(id: string, key: string, value: string) = # TODO: refactoring
    let entry = db.queryOne equal("id", id)
    let db_id = entry["_id"].getStr
    db[db_id][key] = newJString(value)
    db.flush()

proc get_store*(id: string, key: string): string =
    let entry = db.queryOne equal("id", id)
    entry[key].getStr

iterator get_uids*(): (string, string) =
    for x in db:
        yield (x["id"].getStr, x["email"].getStr)
