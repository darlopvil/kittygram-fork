local html = require("lib.instagram.web.html")
local user_db = require("models.users")
local html_request = html.request
local helpers = require("lib.helpers")
local errors = helpers.create_error
local get_grid = require("lib.instagram.web.user.grid")
local get_user_info = require("lib.instagram.web.user.info")
local timeline = require("lib.instagram.web.user.timeline")
local cache = require("lib.cache")

-- Anonymous (cached) profile info, used to detect private and missing
-- accounts before requesting their posts. Instagram answers posts requests for
-- a private account with require_login, which is handled as a rate limit and
-- puts that query on cooldown for every profile. When the info is not cached,
-- it comes from the anonymous profile page, the same request the grid view
-- makes (and caches): the standalone profile info query no longer works
-- anonymously (error 1357054).
local function get_private_info(username)
    local info = cache.query_item("ig:user:" .. username)
    if info == ngx.null or (type(info) == "table" and info.has_errors) then
        local grid_user = get_grid(username, nil, "all")
        if type(grid_user) ~= "table" then
            return nil
        end
        if grid_user.has_errors then
            info = grid_user
        elseif type(grid_user.grid) == "table" and grid_user.grid.error_type == "not_found" then
            -- For a missing profile the page has no user data: the posts
            -- formatter reports not_found, while the info falls back to the
            -- broken anonymous query and only reports an unknown error.
            info = grid_user.grid
        else
            info = grid_user.info
        end
    end
    if type(info) == "table" and info.is_private == true then
        return info
    end
    -- Missing profiles are reported as such, without requesting their posts.
    if type(info) == "table" and info.has_errors and info.error_type == "not_found" then
        return nil, info
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
    local private_info, not_found = get_private_info(username)
    if not_found then
        return not_found
    end
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
