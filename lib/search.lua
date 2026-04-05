local instagram_graphql_request = require("lib.send_instagram_graphql_request")
local queries = require("lib.structures").queries
local helpers = require("lib.helpers")
local errors = require("lib.structures").errors

local function search(query)

    local payload, doc_id = queries.search(query)
    local search_request = instagram_graphql_request(payload, doc_id, "search")
    local search_results = search_request

    if search_results.errors then
        return errors.unknown{ blob = search_results }
    elseif helpers.check_nested_field(search_results, "data", "xdt_api__v1__fbsearch__topsearch_connection") then
        return search_results.data.xdt_api__v1__fbsearch__topsearch_connection
    end

    return errors.unknown{ blob = search_results }
end

return search
