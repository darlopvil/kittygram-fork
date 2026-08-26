local http = require("resty.http")
local json = require("cjson")

-- Fetch a list of highlights for a given user.
-- Not in use currently as viewing highlights requires auth.
local function get_highlights(userid)
    local httpc = http.new()
    -- Instagram's graphql queries sometimes use get requests.
    local highlights_request = httpc:request_uri(
        "https://www.instagram.com/graphql/query?query_id=9957820854288654&user_id="
            .. userid
            .. "&include_reel=true&include_suggested_users=false&include_logged_out_extras=true&include_live_status=false&include_highlight_reels=true"
    )

    local highlights = json.decode(highlights_request.body)

    return highlights
end

return get_highlights
