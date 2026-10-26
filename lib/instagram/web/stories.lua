-- Stories and highlights through the web session (use_for.stories).
-- Only the media is requested; nothing marks a story as seen.
local cache = require("lib.cache")
local graphql = require("lib.instagram.web.graphql")
local helpers = require("lib.helpers")
local json = require("cjson")
local user_db = require("models.users")
local errors = helpers.create_error

local function not_null(value)
    if value == nil or value == json.null then
        return nil
    end
    return value
end

local function format_item(item, reel_user)
    local id = not_null(item.pk) or not_null(item.id)
    local formatted = {
        id = id,
        timestamp = not_null(item.taken_at),
        expiring_at = not_null(item.expiring_at),
        -- used by the download links to name files
        shortcode = "story_" .. tostring(id or ""),
        user = reel_user,
    }
    local image = helpers.check_nested_field(item, "image_versions2", "candidates", 1, "url")
    local video = helpers.check_nested_field(item, "video_versions", 1, "url")
    if type(video) == "string" then
        formatted.video_url = video
        formatted.video_thumbnail = type(image) == "string" and image or nil
    elseif type(image) == "string" then
        formatted.image_url = image
    end
    return formatted
end

local function format_reel(reel)
    local user = type(reel.user) == "table" and reel.user or {}
    local reel_user = {
        username = not_null(user.username),
        profile_picture = not_null(user.profile_pic_url),
        id = not_null(user.pk) or not_null(user.id),
        is_verified = not_null(user.is_verified),
    }
    local formatted = {
        id = not_null(reel.id),
        title = not_null(reel.title),
        reel_type = not_null(reel.reel_type),
        user = reel_user,
        items = {},
    }
    for _, item in ipairs(type(reel.items) == "table" and reel.items or {}) do
        if type(item) == "table" then
            table.insert(formatted.items, format_item(item, reel_user))
        end
    end
    return formatted
end

local function fetch_reel(reel_id, cache_key, expire_type)
    local cached = cache.query_item(cache_key)
    if cached ~= ngx.null then
        return cached
    end

    local payload, doc_id = graphql.queries.reels_media { reel_id }
    local request = graphql.request(payload, doc_id, "stories")
    if request.has_errors then
        return request
    end

    local reels = helpers.check_nested_field(request, "data", "xdt_api__v1__feed__reels_media", "reels_media")
    local reel
    if type(reels) == "table" and type(reels[1]) == "table" then
        reel = format_reel(reels[1])
    else
        -- No active stories: Instagram returns an empty list.
        reel = { id = reel_id, items = {} }
    end
    cache.cache_item(cache_key, reel, expire_type)
    return reel
end

-- Active stories of a profile.
local function get_stories(username)
    local match = ngx.re.match(username, "^[a-zA-Z0-9_\\.]+$", "jo")
    if not match or #username > 30 then
        return errors.not_found { message = "Username is invalid." }
    end

    local user_id
    local known = user_db.get_user(username)
    if known then
        user_id = known.id
    end
    if not user_id then
        -- Anonymous profile lookup (cached, and indexes the profile).
        local profile = require("lib.instagram").get_user(username, nil, "all", "grid")
        if profile.has_errors then
            return profile
        end
        if type(profile.info) == "table" and not profile.info.has_errors then
            user_id = profile.info.id
        end
    end
    if not user_id then
        return errors.not_found { message = "User not found." }
    end

    return fetch_reel(tostring(user_id), "ig:stories:" .. tostring(user_id), "stories")
end

-- One highlight, by its numeric id.
local function get_highlight(id)
    id = tostring(id or "")
    if not id:match("^%d+$") then
        return errors.not_found { message = "Highlight id is invalid." }
    end
    return fetch_reel("highlight:" .. id, "ig:highlight:" .. id, "highlights")
end

-- Highlights tray of a profile: { items = { { id, title, image }, ... } }.
local function get_highlights_tray(user_id)
    local key = "ig:highlights:" .. tostring(user_id)
    local cached = cache.query_item(key)
    if cached ~= ngx.null then
        return cached
    end

    local payload, doc_id = graphql.queries.highlights_tray(tostring(user_id))
    local request = graphql.request(payload, doc_id, "stories")
    if request.has_errors then
        return request
    end

    local tray = { items = {} }
    local edges = helpers.check_nested_field(request, "data", "highlights", "edges")
    for _, edge in ipairs(type(edges) == "table" and edges or {}) do
        local node = type(edge) == "table" and edge.node
        if type(node) == "table" and type(node.id) == "string" then
            local id = node.id:match("^highlight:(%d+)$")
            if id then
                local cover = helpers.check_nested_field(node, "cover_media", "cropped_image_version", "url")
                if type(cover) ~= "string" then
                    cover = helpers.check_nested_field(node, "cover_media", "full_image_version", "url")
                end
                table.insert(tray.items, {
                    id = id,
                    title = not_null(node.title) or "",
                    image = type(cover) == "string" and cover or nil,
                })
            end
        end
    end
    cache.cache_item(key, tray, "highlights")
    return tray
end

return {
    get_stories = get_stories,
    get_highlight = get_highlight,
    get_highlights_tray = get_highlights_tray,
}
