local schema = require("lapis.db.schema")
local db = require("lapis.db")
local types = schema.types

local schema = require("lapis.db.schema")
local db = require("lapis.db")
local types = schema.types

return {
    [1] = function()
        schema.create_table("user_ids", {
            { "id", types.id },
            { "username", types.text },    -- Changed from types.varchar
            { "user_id", types.text },     -- Changed from types.varchar
            "PRIMARY KEY (username)"
        })
    end,
    [1779735501] = function()
        schema.create_table("api_codes", {
            { "id", types.id },
            { "code", types.text },        -- Changed from types.varchar
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
        -- Check if columns already exist (idempotent)
        local res = db.query("PRAGMA table_info(user_ids)")
        local has_profile_picture = false
        local has_is_verified = false

        for _, col in ipairs(res) do
            if col.name == "profile_picture" then
                has_profile_picture = true
            end
            if col.name == "is_verified" then
                has_is_verified = true
            end
        end

        if not has_profile_picture then
            schema.add_column("user_ids", "profile_picture", types.text{ null = true })
        end
        if not has_is_verified then
            schema.add_column("user_ids", "is_verified", types.integer{ default = 0 })
        end
    end,
    [1785761674] = function()
        -- This migration will now create proper TEXT columns
        db.query("BEGIN TRANSACTION;")

        -- Drop FTS dependencies
        db.query("DROP TABLE IF EXISTS user_ids_fts;")
        db.query("DROP TRIGGER IF EXISTS user_ids_ai;")
        db.query("DROP TRIGGER IF EXISTS user_ids_ad;")
        db.query("DROP TRIGGER IF EXISTS user_ids_au;")

        -- Rename old table
        db.query("ALTER TABLE user_ids RENAME TO user_ids_old;")

        -- Create new table with TEXT columns
        db.query([[
            CREATE TABLE user_ids (
                username TEXT PRIMARY KEY,
                user_id TEXT,
                profile_picture TEXT,
                is_verified INTEGER DEFAULT 0
            );
        ]])

        -- Copy data (dropping the id column entirely)
        db.query([[
            INSERT INTO user_ids (username, user_id, profile_picture, is_verified)
            SELECT username, user_id, profile_picture, is_verified
            FROM user_ids_old;
        ]])

        -- Drop old table
        db.query("DROP TABLE user_ids_old;")

        -- Recreate FTS5 table and populate
        db.query([[
            CREATE VIRTUAL TABLE user_ids_fts USING fts5(
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

        -- Recreate triggers
        db.query([[
            CREATE TRIGGER user_ids_ai
            AFTER INSERT ON user_ids
            BEGIN
                INSERT INTO user_ids_fts(rowid, username)
                VALUES(new.rowid, new.username);
            END
        ]])
        db.query([[
            CREATE TRIGGER user_ids_ad
            AFTER DELETE ON user_ids
            BEGIN
                INSERT INTO user_ids_fts(user_ids_fts, rowid)
                VALUES('delete', old.rowid);
            END
        ]])
        db.query([[
            CREATE TRIGGER user_ids_au
            AFTER UPDATE ON user_ids
            BEGIN
                INSERT INTO user_ids_fts(user_ids_fts, rowid)
                VALUES('delete', old.rowid);
                INSERT INTO user_ids_fts(rowid, username)
                VALUES(new.rowid, new.username);
            END
        ]])

        db.query("COMMIT;")
    end
}
