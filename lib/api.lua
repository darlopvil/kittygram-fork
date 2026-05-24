local lapis = require("lapis")
local app = lapis.Application()
local respond_to = require("lapis.application").respond_to
local test_redis = require("lib.cache").test_redis
local config = require("lapis.config").get()
local web_state = ngx.shared.web_state
local json = require("cjson")
local gql_documents = require("lib.instagram.web.graphql").doc_ids

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
    self.res.headers["Access-Control-Allow-Origin"] = "*"
    self.res.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, OPTIONS"
    self.res.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"

    -- Handle preflight here so it applies to all routes
    if ngx.req.get_method() == "OPTIONS" then
        return self:write({ status = 204 })
    end
end)

app:get("/api/status(/)", function(self)
    return { json = {
        redis = test_redis(),
        ratelimits = get_ratelimits(),
        request_counts = get_request_counts()
    }}
end)

app:get("/api/info(/)", function(self)
    return { json = {
        about = config.about_message,
        atom_enabled = config.enable_atom
    }}
end)

return app
