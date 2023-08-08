struct URL
    scheme
    domain
    path
    query
    hash
end

function parseurl(url::String)
    schemesp = split(url, "://", limit=2)

    if length(schemesp) == 1
        scheme = "http"
    else
        scheme = schemesp[1]
    end

    dlm = r"^(?:http(s)?:\/\/)?[\w.-]+(?:\.[\w\.-]+)+[\w\-\._~:/?#[\]@!\$&'\(\)\*\+,;=.]+$"
    pathsp = split(last(scheme), "/", limit = 2)

    if length(pathsp) == 2
        domain = pathsp[1]
    else
        domain = nothing
    end

    querysp = split(last(pathsp), "?")

    if length(querysp) == 2
        if domain == nothing
            domain = querysp[1]
        else
            path = querysp[1]
        end
    else
        path = nothing
    end

    hashsp = split(last(querysp), "#")

    if length(hashsp) == 2
        if domain == nothing
            domain = hashsp[1]
        else
            query = 0
        end
    end


    return URL(scheme[1], domain, path, query, hash)
end
