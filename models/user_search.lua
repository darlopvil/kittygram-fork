local db = require("lapis.db")

local function sanitize_fts_query(query)
    if query == nil then
        query = ""
    end

    query = tostring(query)
    query = query:gsub("%z", "")
    query = query:gsub('"', '""')

    return '"' .. query .. '"'
end

-- function to check for usernames based on the ids table.
local function user_search(username)
    -- fts5 crashes if the username is an empty string.
    if username == "" then
        return {}
    end

    local res = db.query([[
        SELECT
        u.id,
        u.username,
        u.user_id,
        u.profile_picture,
        u.is_verified,
        fts.rank
        FROM user_ids u
        JOIN user_ids_fts fts ON u.rowid = fts.rowid
        WHERE user_ids_fts MATCH ?
        ORDER BY fts.rank ASC
        LIMIT 20;
    ]], sanitize_fts_query(username))

    local processed_results = {}
    for _, item in ipairs(res) do
        if item.is_verified and item.is_verified == 1 then
            item.is_verified = true
        else
            item.is_verified = false
        end
        table.insert(processed_results, item)
    end
    return processed_results
end

return user_search
