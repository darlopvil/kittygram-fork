local config = require("lapis.config")

local themes = require("conf.themes")
local proxies = require("conf.proxies")
local cache = require("conf.cache")


-- more configurations in the /conf directory.

config({"development", "production", "docker"}, {
  server = "nginx",
  default_theme = "auto",
  ipv6 = "off", -- change this to "on" to allow requests over ipv6. Will default to ipv4 otherwise.
  resolver = "8.8.8.8", -- DNS resolver, currently set to google's DNS server.
  trusted_certificate = "/etc/ssl/certs/ca-certificates.crt", -- a path to a file containing trusted CA certs. See: https://github.com/openresty/lua-nginx-module#lua_ssl_trusted_certificate
  themes = themes, -- see: conf/themes.lua
  proxies = proxies, -- see: conf/proxies.lua
  cache = cache, -- see: conf/cache.lua
  enable_atom = false, -- Whether to create Atom (better rss; supported by basically everything rss supports) feeds for users. Disabled by default due to the concerns mentioned here: https://cadence.moe/blog/2022-09-01-discontinuing-bibliogram
  base_atom_path = "http://localhost:8081/", -- Base path to use for generating links in atom feeds. Requires the trailing slash.
  post_fetch_mode = "graphql", -- The method used to fetch posts. Can also be `web`, to fetch posts through html pages (this can break easily), graphql or graphql_root.
  about_message = "<p>The operator of this instance has not written a message yet.</p>", -- The about message to display on the homepage of your instance. Can contain any HTML.
  web_session = { -- **Really** basic session/auth support. Do not expect an account used here to survive.
    cookies = false, -- Replace with session cookies.
    -- Specify which endpoints to use auth for.
    use_for = {
        search = true,
        posts = true, -- ONLY works is `post_fetch_mode` if not set to web.
        comments = true,
        user_posts = true,
        user_info = true,
    }
  },
  include_debug_headers = false, -- Whether to include debug headers (mentions whether cache was hit; which endpoints were accessed.)
  ratelimits = {
    cooldown_on_ratelimit = true, -- If set to true, your instance will block requests until a ratelimit is over.
    window_length = 11 * 60, -- Instagram ratelimits based on an 11 minute sliding window. Here, you can set a custom window length.
    request_limit = 194, -- The number of requests to allow per-window.
  },
  secret = "CHANGE_THIS!", -- The secret used to sign tokens. Change this.
  require_api_token = true, -- Whether to require a token to use the api. Does not apply to the status or info endpoints.
  api_token_expire_length = 365 * 86400, -- How long an api token should last for before expiring, in seconds.
  sqlite = {
    database = "kittygram.sqlite"
  },
  redis = {
    host = "127.0.0.1",
    port = 6379
  },
  instances_list = "https://codeberg.org/irelephant/kittygram/raw/branch/main/instances.json"
})

config("development", {
  port = "8081",
  code_cache = "off",
  num_workers = "1",
  allow_json = true, -- allows json responses if the `json` get param is set to true. Useful for debugging.
})

config("production", {
  port = "80",
  code_cache = "on",
  num_workers = "4",
  allow_json = false,
})

-- configurations specific to docker.
-- this environment also checks for environment variables.
config("docker", {
  port = os.getenv("PORT") or "80",
  secret = os.getenv("SECRET") or "CHANGE_THIS!!",
  default_theme = os.getenv("DEFAULT_THEME") or "auto",
  code_cache = os.getenv("CODE_CACHE") or "on",
  num_workers = os.getenv("NUM_WORKERS") or "4",
  allow_json = os.getenv("ALLOW_JSON") == "true" or false,
  enable_atom = os.getenv("ENABLE_ATOM") == "true" or false,
  base_atom_path = os.getenv("BASE_ATOM_PATH") or "http://localhost/", -- The base path for generating links in atom feeds. Requires the trailing slash.
  resolver = os.getenv("RESOLVER") or "127.0.0.11",
  ratelimits = {
      cooldown_on_ratelimit = os.getenv("COOLDOWN_ON_RATELIMIT") == "true" or true,
      window_length = tonumber(os.getenv("RATELIMIT_WINDOW_SIZE")) or 11 * 60,
      request_limit = tonumber(os.getenv("RATELIMIT_REQUEST_LIMIT")) or 194
  },
  about_message = os.getenv("ABOUT_MESSAGE") or "<p>The operator of this message has not written an about message yet.",
  require_api_token = os.getenv("REQUIRE_API_TOKEN") ~= "false",
  api_token_expire_length = tonumber(os.getenv("API_TOKEN_EXPIRE_LENGTH")) or 365 * 86400,
  redis = {
    host = os.getenv("REDIS_HOST") or "redis",
    port = tonumber(os.getenv("REDIS_PORT")) or 6379,
  }
})
