module Forms

import Base: show, string, hash, ==, getindex, lastindex, iterate

import DataStructures as ds

abstract type Form end

function show(io::IO, mime::MIME"text/plain", s::Form)
  print(io, string(s))
end

struct Pair <: Form
  head
  tail
end

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

function tailstring(c::Union{Vector, ds.Sequential})
  ds.into(" ", map(string) ∘ ds.interpose(" "), c)
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

# A keyword is a name intended for use soley as a name. It should mean something
# to humans who read it.
struct Keyword <: Form
  names::Vector{String}
end

const basehash = hash(":")

hash(k::Keyword) = ds.transduce(ds.map(hash), xor, basehash, k.names)

Base.:(==)(x::Keyword, y::Keyword) = x.names == y.names

function string(s::Keyword)
  ds.into(":", ds.map(string) ∘ ds.interpose("."), s.names)
end

# A Symbol is a name standing in for another value and is not well defined
# without knowing that value.
struct Symbol <: Form
  names::Vector{String}
end

# REVIEW: Two symbols are only the same if they are syntactically and
# semantically the same. Of course two symbols that *mean the same thing* could
# also be considered equal, even if they're "different symbols". So maybe only
# the second check is important...
function Base.:(==)(x::Symbol, y::Symbol)
  x.names == y.names
end

function string(s::Symbol)
  ds.into("", ds.map(string) ∘ ds.interpose("."), s.names)
end

struct Immediate <: Form
  content
end

string(f::Immediate) = "~" * string(f.content)


end # module
