local config = require("lapis.config").get()
local lapis = require("lapis")
local app = lapis.Application()
local date = require("date")
local helpers = require("lib.helpers")
local version = require("version")

local locales = require("i18n.languages")

app:enable("etlua")
app.layout = require("views.layout")
local api = require("lib.api")
local atom = require("lib.atom")
local media_proxy = require("lib.media_proxy")

app:include(media_proxy)
app:include(atom)
app:include(api)

local instagram = require("lib.instagram")
local stories = require("lib.instagram.web.stories")

math.randomseed(os.time())

-- generate the "view on instagram" link and set the theme.
app:before_filter(function(self)
    self.version = version -- set the version number
    self.view_on_instagram_link = "https://www.instagram.com" .. self.req.parsed_url.path
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

-- Set the language.
-- TODO: Accept-Language header support (currently only reads preferences)
app:before_filter(function(self)
    local language_code = self.session.language or "en"
    if not locales[language_code] then
        language_code = "en"
    end
    self.strings = locales[language_code].strings
end)

-- set cookie attributes. This code sets cookies to last for 7300 days.
app.cookie_attributes = function(self)
    local expires = date(true):adddays(7300):fmt("${http}")
    return "Expires=" .. expires .. "; Path=/; HttpOnly"
end

local function render_error(self, error)
    -- Raw Instagram responses can contain the session account's data and
    -- tokens: keep them out of pages and logs unless explicitly enabled.
    self.show_error_details = config.show_error_details == true
    local info = error.error_info or {}
    local message = tostring(info.message or info.error_message)
    local blob = info.blob
    if self.show_error_details and blob and blob ~= "null" then
        ngx.log(ngx.WARN, "[error] ", tostring(error.error_type), ": ", message, " | blob: ", string.sub(tostring(blob), 1, 2000))
    else
        ngx.log(ngx.WARN, "[error] ", tostring(error.error_type), ": ", message)
    end
    self.error = error

    if error.error_type == "not_found" or error.error_type == "route_not_defined" then
        self.page_title = "Not Found | Kittygram"
        return { status = 404, render = "error" }
    elseif error.error_type == "ratelimited" then
        self.page_title = "Ratelimited | Kittygram"
        return { status = 503, render = "error" }
    elseif error.error_type == "null_content" then
        self.page_title = "Unavailable | Kittygram"
        return { status = 410, render = "error" }
    elseif error.error_type == "network_error" then
        self.page_title = "Error | Kittygram"
        return { status = 500, render = "error" }
    elseif error.error_type == "blocked" then
        self.page_title = "Blocked | Kittygram"
        return { status = 502, render = "error" }
    else
        self.page_title = "Error | Kittygram"
        return { status = 500, render = "error" }
    end
end

app:get("/", function(self)
    self.about_message = config.about_message
    self.page_title = "kittygram"
    return { render = "index" }
end)

local function show_post(self)
    local post, comments = instagram.get_post(self.params.shortcode, self.params.cursor)

    if post.has_errors then
        return render_error(self, post)
    else
        self.post = post
        self.comments = comments

        if self.params.json == "true" and config.allow_json then
            return { json = { post, comments } }
        end
        self.page_title = "A post by " .. post.user.username
        return { render = "post" }
    end
end

app:get("/p/:shortcode(/)", show_post)
app:get("/:username/p/:shortcode(/)", show_post)
app:get("/reel/:shortcode(/)", show_post)
app:get("/:username/reel/:shortcode(/)", show_post)
app:get("/reels/:shortcode(/)", show_post)
app:get("/:username/reels/:shortcode(/)", show_post)
app:get("/p/:shortcode/embed(/)", show_post)
app:get("/reel/:shortcode/embed(/)", show_post)

-- Active stories of a profile, needs the web session (use_for.stories).
local function show_stories(self)
    if not helpers.session_enabled_for("stories") then
        return render_error(self, helpers.create_error.feature_not_supported())
    end
    local reel = stories.get_stories(self.params.id)
    if reel.has_errors then
        return render_error(self, reel)
    end
    self.reel = reel
    self.username = self.params.id
    self.page_title = "Stories by @" .. self.params.id .. " | Kittygram"
    return { render = "stories" }
end

app:get("/:username(/:path)(/)", function(self)
    -- /stories/<user> matches this route before the stories one.
    if self.params.username == "stories" and self.params.path then
        self.params.id = self.params.path
        return show_stories(self)
    end

    self.selectors = {}

    local feed_type
    if self.params.path == "reels" then
        feed_type = "reels"
        self.selectors.selected_feed = "reels"
    elseif self.params.path then
        return render_error(self, helpers.create_error.route_not_defined())
    else
        feed_type = "all"
        self.selectors.selected_feed = "all"
    end

    -- Anonymously, Instagram only serves profile posts as a grid (thumbnails).
    -- List and tile views need full media, which needs the web session; the
    -- reels tab is always a grid. Unavailable views fall back to the grid.
    local timeline_views = helpers.session_enabled_for("user_posts") and feed_type ~= "reels"
    self.is_grid_only = not timeline_views

    local view_type
    if timeline_views and (self.params.view == "timeline" or self.params.view == "tile") then
        view_type = self.params.view
    else
        view_type = "grid"
    end
    self.selectors.selected_view = view_type

    local user = instagram.get_user(self.params.username, self.params.after, feed_type, view_type)

    if user.has_errors then
        return render_error(self, user)
    elseif user.grid and user.grid.has_errors then
        return render_error(self, user.grid)
    elseif user.timeline and user.timeline.has_errors then
        return render_error(self, user.timeline)
    else
        if config.enable_atom then
            self.atom_link = "/" .. self.params.username .. "/atom.xml"
        end

        self.user = user

        if self.params.json == "true" and config.allow_json then
            return { json = user }
        end
        if not user.info.has_errors then
            self.username = user.info.username
        else
            -- fall back to the param if the username isn't available
            self.username = self.params.username
        end
        -- Stories and highlights need the web session.
        if
            helpers.session_enabled_for("stories")
            and feed_type == "all"
            and type(user.info) == "table"
            and not user.info.has_errors
            and not user.info.is_private
            and user.info.id
        then
            self.stories_enabled = true
            local tray = stories.get_highlights_tray(user.info.id)
            if type(tray) == "table" and not tray.has_errors then
                self.highlights = tray.items
            end
        end

        self.page_title = "@" .. self.username .. " | kittygram"

        return { render = "user" }
    end
end)

-- Stories and highlights need the web session (use_for.stories).
app:get("/stories/highlights/:id(/)", function(self)
    if not helpers.session_enabled_for("stories") then
        return render_error(self, helpers.create_error.feature_not_supported())
    end
    local reel = stories.get_highlight(self.params.id)
    if reel.has_errors then
        return render_error(self, reel)
    end
    self.reel = reel
    self.username = reel.user and reel.user.username
    self.page_title = (reel.title or "Highlight") .. " | Kittygram"
    return { render = "stories" }
end)

app:get("/stories/:id(/:media_id)(/)", show_stories)

app:get("/search(/)", function(self)
    local instagram_url_regex = [[^(?:https?://)?(?:www\.)?instagram\.com/(?:p|reel|[^/]+/(?:p|reel))/([A-Za-z0-9_-]+)/?(?:\?.*)?$]]
    if self.params.q then
        -- check if a url leads to an instagram post, if so, redirect to that post.
        local url_match = ngx.re.match(self.params.q, instagram_url_regex, "jo")
        if url_match and url_match[1] then
            return { redirect_to = "/p/" .. tostring(url_match[1]) }
        end

        local search_results = instagram.search.search(self.params.q)
        if search_results.has_errors then
            return render_error(self, search_results)
        end
        self.page_title = 'Search for "' .. self.params.q .. '" | kittygram'
        self.search_query = self.params.q
        self.search_results = search_results

        return { render = "search_results" }
    else
        self.page_title = "Search | kittygram"
        return { render = "search" }
    end
end)

app:get("/popular(/)", function(self)
    local popular_page = instagram.search.popular_page()
    if popular_page.has_errors then
        return render_error(self, popular_page)
    end
    self.popular = popular_page
    self.page_title = "Popular | Kittygram"

    return { render = "popular" }
end)

app:get("/popular/:query(/)", function(self)
    local explore_results = instagram.search.explore(self.params.query, self.params.after)
    if explore_results.has_errors then
        return render_error(self, explore_results)
    end
    self.results = explore_results
    self.explore_query = self.params.query
    self.page_title = "Explore " .. self.params.query .. " | Kittygram"
    return { render = "explore" }
end)

-- RIP to instagram user "settings".
app:get("/settings(/)", function(self)
    self.languages = locales
    self.themes = config.themes
    if self.session.language then
        self.selected_language = self.session.language
    else
        self.selected_language = "en"
    end
    if self.session.theme then
        self.selected_theme = self.session.theme
    else
        self.selected_theme = config.default_theme
    end
    if self.session.disable_video_proxying == "on" then
        self.disable_video_proxying = true
    end
    if self.session.sticky_navbar ~= "off" then
        self.sticky_navbar = true
    end

    self.page_title = "Settings | Kittygram"
    return { render = "settings" }
end)

app:post("/settings/save(/)", function(self)
    self.session.language = self.params.language
    self.session.theme = self.params.theme
    self.session.disable_video_proxying = self.params.disable_video_proxying
    if self.params.sticky_navbar == "on" then
        self.session.sticky_navbar = "on"
    else
        self.session.sticky_navbar = "off"
    end

    return { redirect_to = "/" }
end)

app:post("/settings/reset(/)", function(self)
    self.session.language = nil
    self.session.theme = nil
    self.session.disable_video_proxying = nil
    self.session.sticky_navbar = "on"
    return { redirect_to = "/" }
end)

app:get("/*", function(self)
    return render_error(self, helpers.create_error.route_not_defined())
end)

return app
