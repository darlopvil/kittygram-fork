local lapis = require("lapis")
local util = require("lapis.util")
local config = require("lapis.config").get()
local app = lapis.Application()
local date = require("date")
local helpers = require("lib.helpers")

app:enable("etlua")
app.layout = require("views.layout")
local media_proxy = require("lib.media_proxy")
app:include(media_proxy)


local get_post = require("lib.get_post")
local get_user = require("lib.user")
local search = require("lib.search")
local get_comments = require("lib.get_comments")

-- welcome to the soup


-- generate the "view on instagram" link and set the theme.
app:before_filter(function(self)
    self.view_on_instagram_link = "https://www.instagram.com" ..
                                      self.req.parsed_url.path
    if self.session.theme and config.themes[self.session.theme] then
        local theme = config.themes[self.session.theme]
        self.css_url = theme.url

        if theme.uses_base_theme then
            self.uses_base_theme = true
        end
    else
        local theme = config.themes[config.default_theme]
        self.css_url = theme.url

        if theme.uses_base_theme then
            self.uses_base_theme = true
        end
    end
end)


-- set cookie attributes. This code sets cookies to last for 7300 days.
app.cookie_attributes = function(self)
    local expires = date(true):adddays(7300):fmt("${http}")
    return "Expires=" .. expires .. "; Path=/; HttpOnly"
end

app:get("/", function(self)
    self.page_title = "kittygram"
    return { render = "index" }
end)

local function show_post(self)
    local post, comments
    if config.post_fetch_mode == "web" then
        post, comments = get_post.web(self.params.shortcode)
    elseif config.post_fetch_mode == "graphql" then
        post = get_post.graphql(self.params.shortcode)
    else
        ngx.log(ngx.ERR, "post_fetch_mode not set. Falling back to web.")
        post, comments = get_post.web(self.params.shortcode)
    end

    if post.has_errors then
        self.error = post

        if post.error_type == "not_found" then
            self.page_title = "Not Found | Kittygram"
            return { status = 404, render = "error" }
        elseif post.error_type == "ratelimited" then
            self.page_title = "Ratelimited | Kittygram"
            return { status = 503, render = "error"}
        else
            self.page_title = "Error | Kittygram"
            return { status = 500, render = error }
        end
    else
        self.post = post
        if config.post_fetch_mode == "graphql" then
            comments = get_comments(post.id)
        end
        self.comments = comments
        self.page_title = "A post by " .. post.user.username
        if self.params.json == "true" and config.allow_json then
            return { json = post }
        end
        return { render = "post" }
    end
end

app:get("/p/:shortcode(/)", show_post)
app:get("/:username/p/:shortcode(/)", show_post)
app:get("/reel/:shortcode(/)", show_post)
app:get("/:username/reel/:shortcode(/)", show_post)
app:get("/reels/:shortcode(/)", show_post)
app:get("/:username/reels/:shortcode(/)", show_post)



app:get("/:username(/)", function(self)
    local user = get_user(self.params.username, self.params.after)
    if user.has_errors then
        self.error = user
        if user.error_type == "not_found" then
            self.page_title = "Not found | Kittygram"
            return { status = 404, render = "error" }
        elseif user.error_type == "ratelimited" then
            self.page_title = "Ratelimited | Kittygram"
            return { status = 503, render = "error" }
        elseif user.error_type == "blocked" then
            self.page_title = "Blocked | Kittygram"
            return { status = 502, render = "error" }
        else
            self.page_title = "Error | Kittygram"
            return { status = 500, render = "error" }
        end
    else
        self.user = user.user_info
        self.posts = user.posts
        self.end_cursor = user.end_cursor
        if self.params.json == "true" and config.allow_json then
            return { json = user.posts }
        end
        self.page_title = "@" .. user.user_info.username .. " | kittygram"
        return { render = "user" }
    end
end)

app:get("/search(/)", function(self)
    local instagram_url_regex = [[^(?:https?://)?(?:www\.)?instagram\.com/(?:p|reel|[^/]+/(?:p|reel))/([A-Za-z0-9_-]+)/?(?:\?.*)?$]]
    if self.params.q then
        -- check if a url leads to an instagram post, if so, redirect to that post.
        local url_match = ngx.re.match(self.params.q, instagram_url_regex, "jo")
        if url_match and url_match[1] then
            return { redirect_to = "/p/" .. tostring(url_match[1]) }
        end

        local search_results = search(self.params.q)
        self.page_title = "Search for \"" .. self.params.q .. "\" | kittygram"
        self.search_query = self.params.q
        self.search_results = search_results


        return { render = "search_results" }
    else
        self.page_title = "Search | kittygram"
        return { render = "search" }
    end

end)

-- RIP to instagram user "settings".

app:get("/settings(/)", function(self)
    self.themes = config.themes
    if self.session.theme then
        self.selected_theme = self.session.theme
    else
        self.selected_theme = config.default_theme
    end
    if self.session.disable_video_proxying == "on" then
        self.disable_video_proxying = true
    end
    self.page_title = "Settings | Kittygram"
    return { render = "settings" }
end)

app:post("/settings/save(/)", function(self)
    self.session.theme = self.params.theme
    self.session.disable_video_proxying = self.params.disable_video_proxying


    return { redirect_to = "/" }
end)

app:post("/settings/reset(/)", function(self)
   self.session.theme = nil
   self.session.disable_video_proxying = nil
   return { redirect_to = "/" }
end)

app:get("/*", function(self)
    self.error = {
        has_error = true,
        error_type = "route_not_defined",
        error_info = {
            error_message = "No route was defined for this request.",
            error_blob = nil,
        }
    }
    return { status = 404, render  = "error" }
end)


return app
