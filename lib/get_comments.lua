local instagram_graphql_request = require("lib.graphql").request
local queries = require("lib.structures").queries
local helpers = require("lib.helpers")


-- this could probably do with some error handling.
local function get_comments(post_id)

    local payload, doc_id = queries.comments(post_id, "popular")
    local request = instagram_graphql_request(payload, doc_id, "comments")

    return request.data.xdt_api__v1__media__media_id__comments__connection.edges
end

return get_comments
