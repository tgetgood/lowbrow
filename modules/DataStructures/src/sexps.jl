function show(io::IO, mime::MIME"text/plain", s::Sexp)
  print(io, string(s))
end

#### Metadata

# I'm not really using this. I think I'll go with a different mechanism in the
# end. Out of band metadata will make some things easier and others harder, but
# I think it's a better approach.

struct MetaExpr <: Sexp
  metadata::Sexp
  content::Sexp
end

function withmeta(f, m)
  MetaExpr(m, f)
end

function meta(x)
  nothing
end

function meta(x::MetaExpr)
  x.metadata
end

#### Cons cells (Pairs)

struct Pair <: Sexp
  head
  tail
end

# REVIEW: Is this a reasonable way to talk about the length of a cons list?
#
# I'm treating improper lists as lists with the tail as a single element. This
# seems to fit my purposes well, but might come back to bite.
#
# There shouldn't ever be proper cons lists in this language since functions of
# zero args don't exist and we use vectors for storing actual lists of things.
length(c::Pair) = 1 + taillength(c.tail)

taillength(c::Pair) = 1 + taillength(c.tail)
taillength(n::Nothing) = 0
taillength(x) = 1

iterate(c::Pair) = c.head, c.tail
iterate(c::Pair, state::Pair) = iterate(state)
iterate(c::Pair, state::Nothing) = nothing
iterate(c::Pair, x::Any) = x, nothing

function getindex(c::Pair, n)
  if n === 1
    c.head
  else
    getindex(c.tail, n - 1)
  end
end

function tailstring(c::Union{Base.Vector, Sequential})
  into(" ", map(string) ∘ interpose(" "), c)
end

function tailstring(x)
  " . " * string(x)
end

function tailstring(x::Nothing)
  ""
end

function string(c::Pair)
  "(" * string(c.head) * tailstring(c.tail) * ")"
end

#### Keywords

# A keyword is a name intended for use soley as a name. It should mean something
# to humans who read it.
struct Keyword <: Sexp
  names::Base.Vector{String}
end

const basehash = hash(":")

hash(k::Keyword) = transduce(map(hash), xor, basehash, k.names)

Base.:(==)(x::Keyword, y::Keyword) = x.names == y.names

function string(s::Keyword)
  into(":", map(string) ∘ interpose("."), s.names)
end

# TODO: Intern keywords
function keyword(names::String...)
  Keyword(names)
end

function name(x::Keyword)
  x.names[end]
end

#### Syms

# A Sym is a name standing in for another value and is not well defined
# without knowing that value.
struct Sym <: Sexp
  names::Base.Vector{String}
end

function symbol(names::String...)
  Sym(names)
end

function symbol(k::Keyword)
  Sym(k.names)
end

const symhash = hash("#Sym")

hash(s::Sym) = transduce(map(hash), xor, symhash, s.names)

function Base.:(==)(x::Sym, y::Sym)
  x.names == y.names
end

function string(s::Sym)
  into("", map(string) ∘ interpose("."), s.names)
end

function name(x::Sym)
  x.names[end]
end

#### Immediates

struct Immediate <: Sexp
  content
end

string(f::Immediate) = "~" * string(f.content)

#### Other

function name(x::String)
  x
end

function keyword(s::Sym)
  Keyword(s.names)
end
