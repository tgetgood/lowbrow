import Sockets as s
import CodecZlib as cz
import OpenSSL as ssl

function readheaders(rstream)
    headers = Dict{String, String}()

    line = readline(rstream)
    while line != ""
        header, value = split(line, ":", limit = 2)
        headers[lowercase(header)] = strip(value)
        line = readline(rstream)
    end

    return (; headers,)
end

function readbody(headers, rstream)
    #FIXME: I'm not dealing with chunked transfer just now.
    @assert !haskey(headers, "transfer-encoding") || headers["transfer-encoding"] == headers["content-encoding"]

    ce = "content-encoding"
    rawbody = read(rstream, String)
    # Content-Encoding: identity <- technically valid, no compression
    if !haskey(headers, ce) || headers[ce] == "identity"
        return (body = rawbody,)
    else
        enc = headers[ce]
        if enc == "gzip"
            return (body = String(transcode(cz.GzipDecompressor, rawbody)),)
        elseif enc == "deflate"
            return (body = String(transcode(cz.DeflateDecompressor, rawbody)),)
        else
            @assert false "Unsupported compression algorithm: " * enc
        end
    end


end

function parseresponse(rstream)
    # FIXME: This depends on rstream being shared mutable state. Error prone, but
    # maybe performance is important enough here it's okay. Might be an equally
    # fast but safer method.
    vline = readline(rstream)

    version, statuscode, status = split(vline, " ", limit = 3)

    headers = readheaders(rstream)

    body = readbody(headers.headers, rstream)

    merge((; version, statuscode = parse(Int32, statuscode), status), headers, body)
end

reqdefaults = Dict(
    :method => :get,
    :headers => Dict{String, String}(),
    :path => "/",
    :body => "",
    :scheme => :https)

function formatrequest(args)
    br = "\r\n"
    l1 = uppercase(String(args[:method])) * " " * args[:path] * " " * "HTTP/1.0"
    hs = "Host: " * args[:host] * br
    for (k, v) in args[:headers]
        hs *= k * ": " * v * br
    end

    return l1 * br * hs * br * args[:body]
end

# FIXME: This blocks
function request!(req)
    req = merge(reqdefaults, req)
    req[:port] = haskey(req, :port) ? req[:port] : req[:scheme] == :https ? 443 : 80
    msg = formatrequest(req)
    if req[:scheme] == :https
        conn = s.connect(req[:host], req[:port])
G        soc = ssl.SSLStream(conn)
        ssl.hostname!(soc, req[:host])
        ssl.connect(soc)
        write(soc, msg)

        out = ""
        try
            while !eof(soc)
                out *= String(readavailable(soc))
                sleep(1)
            end
        catch e
            @info "Idiocy!!"
        end

        t = tempname()
        write(t, out)
        f = open(t)

        res = parseresponse(f)
        close(f)
        Base.Filesystem.rm(t)
        close(soc)
        return res
    elseif req[:scheme] == :http
        soc = s.connect(req[:host], req[:port])
        write(soc, msg)
        closewrite(soc)
        res = parseresponse(soc)
        close(soc)
        return res
    else
        @assert false "Invalid HTTP scheme: " * String(req[:scheme])
    end
end

function basicprint!(body)
    intag = false
    for char in body
        if char == '<'
            intag = true
        elseif char == '>'
            intag = false
        elseif !intag
            print(char)
        end
    end
end

# res = request!(Dict(:host => "example.com", :headers => Dict("Accept-Encoding" => "gzip"), :scheme => :https))

# basicprint!(res.body)

basic
