local instagram_graphql_request = require("lib.instagram.web.graphql").request
local queries = require("lib.instagram.web.graphql").queries
local helpers = require("lib.helpers")
local cache = require("lib.cache")

-- this could probably do with some error handling.
local function get_comments(post_id)
    local query = cache.query_item("ig:comments:" .. post_id)
    if query ~= ngx.null then
        return query
    end

    local payload, doc_id = queries.comments(post_id, "popular")
    local request = instagram_graphql_request(payload, doc_id, "comments")

    -- Check if an error was caught in the graphql function, if so, return that.
    if request.has_errors then
        return request
    end

    if request.data and request.data.xdt_api__v1__media__media_id__comments__connection then
        cache.cache_item("ig:comments:" .. post_id,  request.data.xdt_api__v1__media__media_id__comments__connection.edges, "comments")
        cache.bulk_save_users.from_comments(request.data.xdt_api__v1__media__media_id__comments__connection)
        return request.data.xdt_api__v1__media__media_id__comments__connection.edges
    end
    -- TODO: proper error handling.
    return {}
end

return get_comments
