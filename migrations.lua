local schema = require("lapis.db.schema")
local db = require("lapis.db")
local types = schema.types

return {
    [1] = function()
    schema.create_table("user_ids", {
        { "id", types.id },
        { "username", types.varchar },
        { "user_id", types.varchar },
        "PRIMARY KEY (username)"
    })
    end,
    [1779735501] = function()
    schema.create_table("api_codes", {
        { "id", types.id },
        { "code", types.varchar },
        { "is_used", types.integer{ default = 0 } },
        { "created_at", types.integer },
    })
    end,
    [1782153491] = function()
    db.query([[
        CREATE VIRTUAL TABLE IF NOT EXISTS user_ids_fts USING fts5(
            username,
            content=user_ids,
            content_rowid=rowid,
            tokenize='trigram'
        )
    ]])
    db.query([[
        INSERT INTO user_ids_fts(rowid, username)
        SELECT rowid, username FROM user_ids
    ]])
    db.query([[
        CREATE TRIGGER IF NOT EXISTS user_ids_ai
        AFTER INSERT ON user_ids
        BEGIN
        INSERT INTO user_ids_fts(rowid, username)
        VALUES(new.rowid, new.username);
        END
    ]])
    db.query([[
        CREATE TRIGGER IF NOT EXISTS user_ids_ad
        AFTER DELETE ON user_ids
        BEGIN
        INSERT INTO user_ids_fts(user_ids_fts, rowid)
        VALUES('delete', old.rowid);
        END
    ]])
    db.query([[
        CREATE TRIGGER IF NOT EXISTS user_ids_au
        AFTER UPDATE ON user_ids
        BEGIN
        INSERT INTO user_ids_fts(user_ids_fts, rowid)
        VALUES('delete', old.rowid);
        INSERT INTO user_ids_fts(rowid, username)
        VALUES(new.rowid, new.username);
        END
    ]])
    end,
    [1782153551] = function()
    schema.add_column("user_ids", "profile_picture", types.text{ null = true})
    schema.add_column("user_ids", "is_verified", types.integer{ default = 0})
    end
}





