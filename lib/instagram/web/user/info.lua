local cache = require("lib.cache")
local graphql = require("lib.instagram.web.graphql")
local user_db = require("models.users")
local formatters = require("lib.formatters")

local function get_user_hover_info(user_id, page_info)
    local key = "ig:user_hover_info:" .. user_id
    local cache_query = cache.query_item(key)
    if cache_query ~= ngx.null then
        return cache_query
    end

    local payload, doc_id = graphql.queries.user_hover_info(user_id)
    local user_info = graphql.query_and_format(payload, doc_id, formatters.format_user_info.from_graphql, {
        purpose = "user_info",
        page_data = page_info
    })

    if user_info.has_errors then
        return user_info
    end

    user_db.save_user(user_info)
    cache.cache_item(key, user_info, "user_info")
    return user_info
end


local function get_user_info(user_id, username, page_info)
    local user_query = cache.query_item("ig:user:" .. username)

    if user_query ~= ngx.null then
        return user_query
    end

    local payload, doc_id = graphql.queries.user_info(user_id)
    local user_info = graphql.query_and_format(payload, doc_id, formatters.format_user_info.from_hover_graphql, {
        purpose = "user_info",
        page_data = page_info
    })

    if user_info.has_errors and user_info.error_type == "ratelimited" then
        return get_user_hover_info(user_id, page_info)
    end

    cache.cache_item("ig:user:" .. username, user_info, "user_info")
    user_db.save_user(user_info)

    return user_info
end

return get_user_info
