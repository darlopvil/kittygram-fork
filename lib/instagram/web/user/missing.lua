-- Why a profile is missing. Instagram answers with the same error page for
-- accounts that never existed and for deleted, deactivated, suspended or
-- renamed ones, logged in or not. If this instance saw the username before,
-- the local index has its user id, which does not change with a rename: asking
-- for that id through the web session (use_for.user_info) tells a renamed
-- account from one that is gone.
local cache = require("lib.cache")
local graphql = require("lib.instagram.web.graphql")
local helpers = require("lib.helpers")
local user_db = require("models.users")
local errors = helpers.create_error

local function format_by_id(data)
    local user = type(data) == "table" and data.user
    if type(user) ~= "table" or type(user.username) ~= "string" then
        return { gone = true }
    end
    return {
        username = user.username,
        id = tostring(user.id or ""),
        profile_picture = user.profile_pic_url,
        is_verified = user.is_verified == true,
    }
end

local function lookup(username, user_id)
    local key = "ig:missing:" .. string.lower(username)
    local cached = cache.query_item(key)
    if cached ~= ngx.null and type(cached) == "table" then
        return cached
    end
    if not helpers.session_enabled_for("user_info") then
        return nil
    end
    local payload, doc_id = graphql.queries.user_info(user_id)
    local result = graphql.query_and_format(payload, doc_id, format_by_id, { purpose = "user_info" })
    if type(result) == "table" and result.has_errors and result.error_type == "not_found" then
        -- Instagram answers an id with no account behind it with an error.
        result = { gone = true }
    elseif type(result) ~= "table" or result.has_errors then
        return nil
    end
    cache.cache_item(key, result, "negative_timeline")
    return result
end

-- Turns a profile's not_found error into one that says what is known.
local function explain(username, original)
    local message = type(original) == "table" and type(original.error_info) == "table" and original.error_info.message or nil
    local known = user_db.get_user(username)

    if not known or not known.id then
        return errors.not_found {
            title = "This account isn't available.",
            description = "Instagram shows the same page for accounts that never existed and for accounts that were deleted, deactivated, suspended or renamed, so there is no way to tell which one this is.",
            message = message,
        }
    end

    local result = lookup(username, known.id)

    if result and result.username and string.lower(result.username) ~= string.lower(username) then
        if result.id ~= "" then
            user_db.save_user(result)
        end
        return errors.not_found {
            title = "This account changed its username.",
            description = "@" .. username .. " is now @" .. result.username .. ".",
            link = { href = "/" .. result.username, text = "Go to @" .. result.username },
            message = message,
        }
    elseif result and result.username then
        return errors.not_found {
            title = "This account isn't available right now.",
            description = "Instagram didn't show the profile, but the account still exists. Try again later.",
            message = message,
        }
    elseif result and result.gone then
        return errors.not_found {
            title = "This account is no longer available.",
            description = "This instance saw @" .. username .. " before, so the account existed, but Instagram no longer returns it: it was deleted, deactivated or suspended.",
            message = message,
        }
    end

    return errors.not_found {
        title = "This account isn't available.",
        description = "This instance saw @" .. username .. " before, so the account existed. It may have been deleted, deactivated, suspended or renamed.",
        message = message,
    }
end

return {
    explain = explain,
}
