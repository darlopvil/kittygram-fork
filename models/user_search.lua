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

-- Usernames only contain lowercase letters, digits, dots and underscores
-- (stored lowercased), so drop anything else: spaces, "@", punctuation...
local function normalize_query(query)
    return (string.lower(tostring(query or "")):gsub("[^a-z0-9._]", ""))
end

-- The trigram tokenizer can't match fewer than 3 characters: use a prefix match.
local function prefix_search(prefix)
    -- "_" is a LIKE wildcard and the only one a normalized query can contain.
    local escaped = prefix:gsub("_", "\\_")
    return db.query(
        [[
        SELECT username, user_id, profile_picture, is_verified
        FROM user_ids
        WHERE username LIKE ? ESCAPE '\'
        ORDER BY length(username) ASC, username ASC
        LIMIT 20;
    ]],
        escaped .. "%"
    )
end

-- function to check for usernames based on the ids table.
local function user_search(username)
    username = normalize_query(username)
    -- fts5 crashes if the username is an empty string.
    if username == "" then
        return {}
    end

    local res
    if #username < 3 then
        res = prefix_search(username)
    else
        res = db.query(
            [[
            SELECT
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
        ]],
            sanitize_fts_query(username)
        )
    end

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
