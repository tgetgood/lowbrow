module Reader

import DataStructures as ds

import ..Forms: ListForm, ValueForm, Symbol, Keyword

struct BufferedStream
    stream::IO
    buffer::Base.Vector{Char}
end

mutable struct StringStream
    stream::String
    index::UInt
end

function read1(s::BufferedStream)
    if length(s.buffer) > 0
       return popfirst!(s.buffer)
    else
        return read1(s.stream)
    end
end

function unread1(s::BufferedStream, c::Char)
    pushfirst!(s.buffer, c)
end

function read1(s::StringStream)
    try
        c = s.stream[s.index]
        s.index = nextind(s.stream, s.index)
        return c
    catch BoundsError
        throw(EOFError())
    end
end

function unread1(s::StringStream, c::Char)
    j = prevind(s.stream, s.index)
    @assert s.stream[j] === c "Cannot pushback char that was not in stream"
    s.index = j
end

function tostream(s::IO)
    BufferedStream(s, [])
end

function tostream(s::String)
    StringStream(s, 1)
end

ts = "łβ∘"

struct ReaderOptions
    until
end


## This will raise an error on EOF. That's normally the right behaviour, but we
## might need a softer try-read sort of fn.
function read1(stream)
    return Base.read(stream, Char)
end

whitespace = r"[\s,]"

iswhitespace(c) = match(whitespace, string(c)) !== nothing

function firstnonwhitespace(stream)
    c::Char = ' '
    while iswhitespace(c)
        c = read1(stream)
    end
    return c
end

function splitsymbolic(x::String)
  split(x, '.')
end

function readkeyword(x)
  Keyword(splitsymbolic(x))
end

function readsymbol(env, x)
  name = readkeyword(x)
  Symbol(env, name)
  end
end

function interpret(env, x::String)
    if startswith(x, ':')
        return readkeyword(x)
    end
    try
        return parse(Int, x)
    catch ArgumentError
    end

    # TODO: Read in floats as rationals.

    if x == "true"
        return true
    elseif x == "false"
        return false
    else
        return readsymbol(env, x)
    end
end

function readsubforms(env, stream, until)
    forms = []
    while true
        t = read(env, stream, ReaderOptions(until))
        if t === :close
            break
        elseif t === nothing
            continue
        else
            push!(forms, t)
        end
    end
    return forms
end

function readlist(env, stream, opts)
  v = readsubforms(env, stream, ')')
  # TODO: Check symbol is in env and maybe pare down the env.
  #
  # Ideally we would merge all of the envs of the subforms and then remove
  # anything extraneous. Small contexts will be useful for compiling and
  # optimising.
  ListForm(env, v[1], ds.vec(v[2:end]))
end

function readvector(env, stream, opts)
    ds.vector(readsubforms(env, stream, ']')...)
end

specialchars = Dict(
    't' => '\t',
    'r' => '\r',
    'n' => '\n',
    'b' => '\b',
    'f' => '\f',
    '"' => '"',
    '\\' => '\\'
)

function stopcondition(base)
    if base == 8
        return function(next)
            !(47 < Int(next) < 56)
        end
    elseif base == 16
        return function(next)
            i = Int(next)
            !(47 < i < 56 || 96 < i < 103 || 64 < i < 71)
        end
    end
end

function unicodestep(stream, sum, base)
    next = read1(stream)
    if stopcondition(base)(next)
        unread1(stream, next)
        sum, true
    else
        sum*base + parse(Int, "0x"*next), false
    end
end

function readunicodehex(stream, ch)
    done = false
    num = parse(Int, "0x"*ch)
    i = 0
    while (!done && i < 3)
        num, done = unicodestep(stream, num, 16)
        i = i + 1
    end
    return Char(num)
end

function readunicodeoctal(stream, ch)
    @assert 47 < Int(ch) && Int(ch) < 56 "Invalid digit"

    out, done = unicodestep(stream, parse(Int, ch), 8)
    if done
        return Char(out)
    end

    out, done = unicodestep(stream, out, 8)

    if out > 377
        throw("Octal escapes must be in the range [0, 377]")
    else
        return Char(out)
    end
end

function readstring(env, stream, opts)
    buf = []
    c = read1(stream)
    while (c != '"')
        if c == '\\'
            next = read1(stream)
            char = Base.get(specialchars, next, nothing)
            if char !== nothing
                push!(buf, char)
            elseif next == 'u'
                next = read1(stream)
                @assert !stopcondition(16)(next) "Invalid unicode escape"
                char = readunicodehex(stream, next)
                push!(buf, char)
            elseif isdigit(next)
                char = readunicodeoctal(stream, next)
                push!(buf, char)
            else
                throw("Invalid escape char: " * next)
            end
        else
            push!(buf, c)
        end
        try
            c = read1(stream)
        catch e
           @error e
        end
    end
    return string(buf...)
end

function readmap(env, stream, opts)
    elements = readsubforms(env, stream, '}')
    @assert length(elements) % 2 === 0 "a map literal must contain an even number of entries"

    res = ds.emptymap
    for i in 1:div(length(elements), 2)
        res = assoc(res, popfirst!(elements), popfirst!(elements))
    end
    return res
end

function readset(env, stream, opts)
    throw("not implemented")
end

function readcomment(env, stream, opts)
    c = read1(stream)
    while c != '\n' && c != '\r'
        c = read1(stream)
    end
end

function readanddiscard(stream, opts)
    read(stream, opts)
    return nothing
end

indirectdispatch = Dict(
    '_' => readanddiscard,
    '{' => readset
)

function readdispatch(stream, opts)
    c = read1(stream)
    reader = Base.get(indirectdispatch, c, nothing)
    if reader === nothing
        throw("Invalid dispatch macro: " * c)
    else
        reader(stream, opts)
    end
end

function readmeta(env, stream, opts)
    meta = read(env, stream, opts)
    val = read(env, stream, opts)
    if isa(meta, ds.Map)
        withmeta(val, meta)
    else
        withmeta(val, assoc(ds.emptymap, meta, true))
    end
end

dispatch = Dict(
    '(' => readlist,
    '[' => readvector,
    '"' => readstring,
    '{' => readmap,
    '#' => readdispatch,
    ';' => readcomment,
    '^' => readmeta

)

delimiter = r"[({\[;]"

function istokenbreak(c)
    iswhitespace(c) ||  match(delimiter, string(c)) !== nothing
end

function readtoken(stream, opts)
    out = ""

    while true
        try
            c = read1(stream)
            if istokenbreak(c) || c === opts.until
                unread1(stream, c)
                break
            else
                out = out*c
            end
        catch e
            if typeof(e) == EOFError
                break
            else
                throw(e)
            end
        end
    end

    return out
end

function read(env, stream, opts)
    c = firstnonwhitespace(stream)

    if opts.until !== nothing && c === opts.until
        return :close
    end

    sub = Base.get(dispatch, c, nothing)

    if sub === nothing
        unread1(stream, c)
        return interpret(env, readtoken(stream, opts))
    else
        return sub(env, stream, opts)
    end
end

function read(env, stream)
    read(env, stream, ReaderOptions(nothing))
end

function read(env, s::String)
    read(env, tostream(s))
end

function read(env, s::IO)
    read(env, tostream(s))
end

# """N.B. This will run forever if `stream` doesn't eventually close"""
function readall(env, stream::BufferedStream)
  forms = []
  while true
    try
      push!(forms, read(env, stream))
    catch EOFError
      return ds.remove(isnothing, forms)
    end
  end
end

function readall(env, x::IO)
  readall(env, tostream(x))
end

function repall(x)
  @info x
  for f in readall(ds.emptymap, x)
    @info f
    println(string(f))
    println()
  end
end

end #module
