local html = require("lib.instagram.web.html")
local user_db = require("models.users")
local html_request = html.request
local helpers = require("lib.helpers")
local errors = helpers.create_error
local get_grid = require("lib.instagram.web.user.grid")
local get_user_info = require("lib.instagram.web.user.info")
local timeline = require("lib.instagram.web.user.timeline")
local cache = require("lib.cache")
local formatters = require("lib.formatters")
local graphql = require("lib.instagram.web.graphql")

-- Anonymous (cached) profile info, used to detect private accounts before
-- requesting their posts. Instagram answers posts requests for a private
-- account with require_login, which is handled as a rate limit and puts that
-- query on cooldown for every profile.
local function get_private_info(username)
    local key = "ig:user:" .. username
    local info = cache.query_item(key)
    if info == ngx.null then
        local query, doc_id = graphql.queries.anon_user_info(username)
        info = graphql.query_and_format(query, doc_id, formatters.format_user_info.from_anon_web_graphql, {
            purpose = "user_info",
        })
        if type(info) == "table" and not info.has_errors and info.username then
            cache.cache_item(key, info, "user_info")
        end
    end
    if type(info) == "table" and info.is_private == true then
        return info
    end
end

local function get_timeline_user(username, cursor, feed_type, is_grid_fallback)
    local user_id, page_data
    local user_query = user_db.get_user(username)
    if user_query then
        user_id = user_query.id
    elseif feed_type ~= "all" then
        local request_url = "https://www.instagram.com/" .. username .. "/"
        if feed_type == "reels" then
            request_url = request_url .. "reels/"
        end

        local request = html_request(request_url, "/%s")
        if not request.has_errors and request.data then
            page_data = request.data
            user_id = page_data["user_id"]
        end
    end

    local posts
    if feed_type == "reels" then
        posts = timeline.get_reel_timeline(user_id, cursor, page_data)
    elseif feed_type == "all" then
        local timeline_posts, derived_user_id = timeline.get_timeline(username, cursor, page_data)
        posts = timeline_posts
        if not user_id then
            user_id = derived_user_id
        end
    end

    local info = get_user_info(user_id, username, page_data)

    if is_grid_fallback then
        return { grid = posts, info = info }
    end

    return { timeline = posts, info = info }
end

-- Timeline-based views never request the posts of a private account.
local function get_timeline_or_private(username, cursor, feed_type, is_grid_fallback)
    local private_info = get_private_info(username)
    if private_info then
        if is_grid_fallback then
            return { info = private_info, grid = { items = {} } }
        end
        return { info = private_info, timeline = { items = {} } }
    end
    return get_timeline_user(username, cursor, feed_type, is_grid_fallback)
end

local function check_ratelimit(item)
    if item and item.has_errors and item.error_type == "ratelimited" then
        return true
    end
end

local function get_user(username, cursor, feed_type, feed_view)
    local match = ngx.re.match(username, "^[a-zA-Z0-9_\\.]+$", "jo")
    if not match or #username > 30 then
        return errors.not_found {
            message = "Username is invalid. Open an issue if this user really exists.",
        }
    end

    if feed_view == "grid" then
        local grid_user = get_grid(username, cursor, feed_type)
        local rate_limited = check_ratelimit(grid_user) or check_ratelimit(grid_user.info) or check_ratelimit(grid_user.grid)
        if rate_limited and feed_type == "all" and helpers.session_enabled_for("user_posts") then
            return get_timeline_or_private(username, cursor, feed_type, true)
        end
        return grid_user
    else
        return get_timeline_or_private(username, cursor, feed_type)
    end
end

return get_user
