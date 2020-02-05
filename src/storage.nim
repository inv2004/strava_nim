import flatdb
import json

var db = newFlatDb("testdb.db", false)
discard db.load()

proc store*(profile: (string, string), accessToken: string) = # TODO: refactoring
    let id = profile[0]
    let email = profile[1]

    discard db.append(%* {"id": id, "email": email, "access_token": accessToken})
    db.flush()

proc upd_store*(id: string, refreshToken: string) = # TODO: refactoring
    let entry = db.queryOne equal("id", id)
    let db_id = entry["_id"].getStr
    db[db_id]["refresh_token"] = newJString(refreshToken)
    db.flush()
