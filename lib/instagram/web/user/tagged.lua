-- Posts a profile is tagged in, through the web session (use_for.tagged).
-- Instagram serves them as a grid: the nodes carry thumbnails, not full media,
-- so each item links to its post page.
local cache = require("lib.cache")
local graphql = require("lib.instagram.web.graphql")
local helpers = require("lib.helpers")
local json = require("cjson")
local user_db = require("models.users")
local errors = helpers.create_error

local CONNECTION = "xdt_api__v1__usertags__user_id__feed_connection"

local function is_set(value)
    return value ~= nil and value ~= json.null
end

local function format_item(node)
    local item = {
        shortcode = node.code,
        id = node.pk,
        alt_text = is_set(node.accessibility_caption) and node.accessibility_caption or nil,
    }

    if is_set(node.display_uri) then
        item.thumbnail = node.display_uri
    elseif
        is_set(node.image_versions2)
        and is_set(node.image_versions2.candidates)
        and node.image_versions2.candidates[1]
    then
        item.thumbnail = node.image_versions2.candidates[1].url
    end

    if node.product_type == "clips" or node.media_type == 2 then
        item.kind = "reel"
    elseif node.product_type == "carousel_container" or node.media_type == 8 then
        item.kind = "carousel"
    else
        item.kind = "post"
    end

    -- The authors of tagged posts go into the local search index.
    local user = node.user
    if type(user) == "table" and is_set(user.username) then
        local id = is_set(user.pk) and user.pk or user.id
        if is_set(id) then
            user_db.save_user {
                username = user.username,
                id = tostring(id),
                profile_picture = is_set(user.profile_pic_url) and user.profile_pic_url or nil,
                is_verified = user.is_verified == true,
            }
        end
    end

    return item
end

local function format_tagged(data)
    local connection = type(data) == "table" and data[CONNECTION]
    if type(connection) ~= "table" then
        return errors.unknown {
            message = "Instagram returned no tagged posts.",
            blob = data,
        }
    end

    local formatted = { items = {} }
    for _, edge in ipairs(is_set(connection.edges) and connection.edges or {}) do
        local node = type(edge) == "table" and edge.node
        if type(node) == "table" and is_set(node.code) then
            table.insert(formatted.items, format_item(node))
        end
    end

    local page_info = connection.page_info
    if is_set(page_info) and page_info.has_next_page and is_set(page_info.end_cursor) then
        formatted.cursor = tostring(page_info.end_cursor)
    end

    return formatted
end

local function get_tagged(user_id, cursor)
    user_id = tostring(user_id or "")
    if not user_id:match("^%d+$") then
        return errors.not_found { message = "Unknown user id." }
    end
    -- Cursors are numeric media ids.
    if cursor and not tostring(cursor):match("^%d+$") then
        return errors.not_found { message = "Invalid cursor." }
    end

    local key = "ig:tagged:" .. user_id .. ":" .. (cursor or "latest")
    local cached = cache.query_item(key)
    if cached ~= ngx.null and type(cached) == "table" and not cached.has_errors then
        return cached
    end

    local payload, doc_id
    if cursor then
        payload, doc_id = graphql.queries.tagged_posts_paginated(user_id, cursor)
    else
        payload, doc_id = graphql.queries.tagged_posts(user_id)
    end

    local tagged = graphql.query_and_format(payload, doc_id, format_tagged, { purpose = "tagged" })
    if type(tagged) ~= "table" or tagged.has_errors then
        return tagged
    end

    cache.cache_item(key, tagged, cursor and "cursored_timeline" or "latest_timeline")
    return tagged
end

return {
    get_tagged = get_tagged,
}
