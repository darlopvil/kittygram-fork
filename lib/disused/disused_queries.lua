local doc_ids = {
    shortcode2 = {
        doc_id = "26713194205046842",
        endpoint = "query",
        method = "POST"
    },
    logged_out_user_posts = {
        doc_id = "7950326061742207",
        endpoint = "query",
        method = "GET"
    },
}
-- queries that aren't used currently.
local unused_queries = {
    -- found in a post page. Query name: PolarisPostRootQuery
    -- seems to be an alternate way to get a post from a shortcode.
    shortcode2 = function()
        return {
            shortcode = "CNrKOqaj1t6",
            __relay_internal__pv__PolarisAIGMMediaWebLabelEnabledrelayprovider = false
        }, doc_ids.shortcode2
    end,
    -- the logged_out posts query. This takes an id rather than a username. Probably doesn't work with cookies/auth.
    logged_out_user_posts = function(user_id, count, after_cursor)
        if not after_cursor then
            after_cursor = json.null
        end
        return {
            id = user_id,
            after = after_cursor,
            first = count
        }, doc_ids.logged_out_user_posts
    end,
}
