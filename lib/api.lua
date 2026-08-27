local lapis = require("lapis")
local app = lapis.Application()
local json_params = require("lapis.application").json_params
local api_codes = require("models.api_codes")
local test_redis = require("lib.cache").test_redis
local config = require("lapis.config").get()
local version = require("version")
local web_state = ngx.shared.web_state
local encoding = require("lapis.util.encoding")
local json = require("cjson")
local gql_documents = require("lib.instagram.web.graphql").doc_ids
local api_endpoints = require("lib.instagram.web.api").endpoints
local instagram = require("lib.instagram")

local function get_ratelimits()
    local ratelimits = {}
    for key, document in pairs(gql_documents) do
        local req_count = web_state:get("graphql:" .. document.doc_id)
        if req_count and req_count > config.ratelimits.request_limit then
            ratelimits[key] = "blocked"
        else
            ratelimits[key] = "ok"
        end
    end
    for key, endpoint in pairs(api_endpoints) do
        local req_count = web_state:get("api:" .. endpoint.path)
        if req_count and req_count > config.ratelimits.request_limit then
            ratelimits[key] = "blocked"
        else
            ratelimits[key] = "ok"
        end
    end

    if config.post_fetch_mode ~= "graphql" then
        local req_count = web_state:get("post_html")
        if req_count and req_count > config.ratelimits.request_limit then
            ratelimits["shortcode"] = "blocked"
        else
            ratelimits["shortcode"] = "ok"
        end
    end
    return ratelimits
end

local function get_request_counts()
    local counts = {}
    local keys = web_state:get_keys()
    for _, key in ipairs(keys) do
        local count = web_state:get(key)
        counts[key] = count
    end
    return counts
end

app:before_filter(function(self)
    local decoded_token = encoding.decode_with_secret((self.req.headers["Authorization"] or ""):gsub("Bearer ", "", 1), config.secret)
    if decoded_token and decoded_token.expires then
        if not (decoded_token.expires < os.time()) then
            self.token_is_valid = true
        end
    end

    self.res.headers["Access-Control-Allow-Origin"] = "*"
    self.res.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, OPTIONS"
    self.res.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"

    -- Handle preflight here so it applies to all routes
    if ngx.req.get_method() == "OPTIONS" then
        return self:write { status = 204 }
    end
end)

local function return_error(err)
    local status
    if err.error_type == "not_found" then
        status = 404
    elseif err.error_type == "ratelimited" then
        status = 503
    elseif err.error_type == "null_content" then
        status = 410
    else
        status = 500
    end
    return { json = err, status = status }
end

app:get("/api/status(/)", function(self)
    return {
        json = {
            redis = test_redis(),
            ratelimits = get_ratelimits(),
            request_counts = get_request_counts(),
        },
    }
end)

app:get("/api/info(/)", function(self)
    return {
        json = {
            about = config.about_message,
            atom_enabled = config.enable_atom,
            version = version or "Unknown",
            api_token_required = config.require_api_token,
        },
    }
end)

app:post(
    "/api/register_token",
    json_params(function(self)
        local timestamp = os.time()

        if not self.params.code then
            return {
                json = {
                    status = "fail",
                    message = "A code is required.",
                },
                status = 400,
            }
        end

        if not api_codes.validate_code(self.params.code) then
            return {
                json = {
                    status = "fail",
                    message = "Code is invalid.",
                },
                status = 400,
            }
        end
        api_codes.mark_code_as_used(self.params.code)

        local token = encoding.encode_with_secret(
            { timestamp = timestamp, expires = timestamp + config.api_token_expire_length, code = self.params.code },
            config.secret
        )
        return { json = {
            status = "ok",
            token = token,
        } }
    end)
)

app:get("/api/post(s)/:shortcode(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    local post, comments = instagram.get_post(self.params.shortcode, self.params.cursor)
    post.comments = comments
    local status_code
    if post.has_errors then
        return return_error(post)
    end

    post.status = "ok"
    return { json = post }
end)

app:get("/api/users/:view_type/:username(/:path)(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    local feed_type
    if self.params.path and self.params.path == "reels" or self.params.path == "reel" then
        feed_type = "reels"
    else
        feed_type = "all"
    end

    local view_type
    if self.params.view_type == "grid" then
        view_type = "grid"
    elseif self.params.view_type == "timeline" then
        view_type = "timeline"
    else
        return {
            json = {
                status = "fail",
                message = "Incorrect view_type (must be `grid` or `timeline`)",
            },
            status = 400,
        }
    end

    local user = instagram.get_user(self.params.username, self.params.cursor, feed_type, view_type)

    if user and user.has_errors then
        return return_error(user)
    end
    if user.timeline and user.timeline.has_errors then
        return return_error(user.timeline)
    end

    if user.info and user.info.has_errors then
        return return_error(user.info)
    end

    user.status = "ok"
    return { json = user }
end)
-- This endpoint is only kept around for compatability.
-- NOTE: remove this soon.
app:get("/api/user/:username(/:path)(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    local feed_type
    if self.params.path and self.params.path == "reels" then
        feed_type = "reels"
    else
        feed_type = "all"
    end

    local user = instagram.get_user(self.params.username, self.params.cursor, feed_type, "timeline")

    if user.timeline and user.timeline.has_errors then
        return return_error(user.timeline)
    end

    if user.info and user.info.has_errors then
        return return_error(user.info)
    end

    -- Rearrange the table structure for compatability.

    user.user_info = {
        full_name = user.info.display_name,
        username = user.info.username,
        id = user.info.id,
        pk = user.info.id,
        is_verified = user.info.is_verified,
        pronouns = user.info.pronouns,
        profile_picture_url = user.info.profile_picture,
        hd_profile_pic_info = {
            url = user.info.hd_profile_picture,
        },
        follower_count = user.info.followers,
        following_count = user.info.following,
        media_count = user.info.media_count,
        is_private = user.info.is_private,
        bio_links = user.info.bio_links,
        biography = user.info.biography,
    }
    user.info = nil
    user.posts = user.timeline.items
    user.end_cursor = user.timeline.cursor
    user.timeline = nil

    user._message = "This endpoint is deprecated and will be removed soon. Please use users/grid or users/timeline instead. "
    user.status = "ok"
    return { json = user }
end)

app:get("/api/search(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    if not self.params.query then
        return {
            json = {
                status = "fail",
                message = "Missing parameter `query`",
            },
            status = 400,
        }
    elseif type(self.params.query) ~= "string" then
        return {
            json = {
                status = "fail",
                message = "Invalid data type for parameter `query`",
            },
            status = 400,
        }
    end

    local query = instagram.search.search(self.params.query)

    if query.has_errors then
        return { json = query }
    end

    query.status = "ok"

    return { json = query }
end)

app:get("/api/popular(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    local items = instagram.search.popular_page()
    if items.has_errors then
        return return_error(items)
    end

    return { json = {
        items = items,
        status = "ok",
    } }
end)

app:get("/api/popular/:query(/)", function(self)
    if config.require_api_token ~= false and not self.token_is_valid then
        return {
            json = {
                status = "fail",
                message = "An API token is required.",
            },
            status = 401,
        }
    end

    local items = instagram.search.explore(self.params.query, self.params.cursor)
    if items.has_errors then
        return return_error(items)
    end

    items.status = "ok"
    return { json = items }
end)

return app
