module Reader

import DataStructures as ds

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
  if x == "."
    ["."]
  else
    split(x, '.')
  end
end

function readkeyword(x)
  ds.Keyword(splitsymbolic(x))
end

function readsymbol(x)
  ds.Symbol(splitsymbolic(x))
end

function interpret(x::String)
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
    return readsymbol(x)
  end
end

function readsubforms(stream, until)
  forms = []
  while true
    t = read(stream, ReaderOptions(until))
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

function readlist(stream, opts)
  subs = readsubforms(stream, ')')

  # REVIEW: This is an ugly hack.
  #
  # But would a null (or other token) terminated list be any better?
  #
  # Remember that the real goal of cons cells here is a syntax to describe
  # applying an arbitrary value to a callable while retaining the near universal
  # convention that callables take a list of arguments passed à la (f x y z).

  n = length(subs)
  # dot application: (f . x)
  if n === 3 && subs[2] == ds.Symbol(["."])
    ast.pair(subs[1], subs[3])
  # list catenation: (f x y z . more)
  elseif subs[end-1] == ds.Symbol(["."])
    ast.pair(subs[1], ast.arglist(ds.into(ds.vec(subs[2:end-2]), subs[end])))
  # standard application: (f x y z)
  else
    ast.pair(subs[1], ast.arglist(subs[2:end]))
  end
end

function readvector(stream, opts)
  ds.vector(readsubforms(stream, ']')...)
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

function readstring(stream, opts)
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

function readmap(stream, opts)
  elements = readsubforms(stream, '}')
  @assert length(elements) % 2 === 0 "a map literal must contain an even number of entries"

  res = ds.emptymap
  for i in 1:div(length(elements), 2)
    res = assoc(res, popfirst!(elements), popfirst!(elements))
  end
  return res
end

function readset(stream, opts)
  throw("not implemented")
end

function readcomment(stream, opts)
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

function readmeta(stream, opts)
  meta = read(stream, opts)
  val = read(stream, opts)
  if isa(meta, ds.Map)
    withmeta(val, meta)
  else
    withmeta(val, assoc(ds.emptymap, meta, true))
  end
end

function readimmediate(stream, opts)
  ast.immediate(read(stream, opts))
end

dispatch = Dict(
  '(' => readlist,
  '[' => readvector,
  '"' => readstring,
  '{' => readmap,
  '#' => readdispatch,
  ';' => readcomment,
  '^' => readmeta,
  '~' => readimmediate
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

function read(stream, opts)
  c = firstnonwhitespace(stream)

  if opts.until !== nothing && c === opts.until
    return :close
  end

  sub = Base.get(dispatch, c, nothing)

  if sub === nothing
    unread1(stream, c)
    return interpret(readtoken(stream, opts))
  else
    return sub(stream, opts)
  end
end

function read(stream)
  read(stream, ReaderOptions(nothing))
end

function read(s::String)
  read(tostream(s))
end

function read(s::IO)
  read(tostream(s))
end

"""N.B. This will run forever if `stream` doesn't eventually close"""
function readall(stream::BufferedStream)
  forms = []
  while true
    try
      push!(forms, read(stream))
    catch EOFError
      return ds.remove(isnothing, forms)
    end
  end
end

function readall(x::IO)
  readall(tostream(x))
end

function repall(x)
  for f in readall(ds.emptymap, x)
    println(string(f))
    println()
  end
end

end #module
