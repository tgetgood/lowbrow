module Forms

import Base: show, string, hash, ==

import DataStructures as ds

abstract type Form end

struct ListForm <: Form
  env::ds.Map
  head::Any
  tail::ds.Vector
end

function string(f::ListForm)
  "(" * string(f.head) * " " * ds.into("", ds.map(string) ∘ ds.interpose(" "), f.tail) * ")"
end

function show(io::IO, mime::MIME"text/plain", s::ListForm)
  print(io, string(s))
end

struct ValueForm <: Form
  env::ds.Map
  content::Any
end

function show(io::IO, mime::MIME"text/plain", s::ValueForm)
  show(io, s.content)
end

# A keyword is a name intended for use soley as a name. It should mean something
# to humans who read it.
struct Keyword
  names::Vector{String}
end

const basehash = hash(":")

hash(k::Keyword) = ds.transduce(ds.map(hash), xor, basehash, k.names)

Base.:(==)(x::Keyword, y::Keyword) = x.names == y.names

function string(s::Keyword)
  ds.into(":", ds.map(string) ∘ ds.interpose("."), s.names)
end

function show(io::IO, mime::MIME"text/plain", s::Keyword)
  print(io, string(s))
end

# A Symbol is a name standing in for another value and is not well defined
# without knowing that value. `env` may contain more that just the definition of
# this symbol, but that isn't required.
struct Symbol <: Form
  env::ds.Map
  name::Keyword
end

# REVIEW: Two symbols are only the same if they are syntactically and
# semantically the same. Of course two symbols that *mean the same thing* could
# also be considered equal, even if they're "different symbols". So maybe only
# the second check is important...
function Base.:(==)(x::Symbol, y::Symbol)
  x.name == y.name && get(env, x.name) == get(env, y.name)
end

function string(s::Symbol)
  ds.into("", ds.map(string) ∘ ds.interpose("."), s.name.names)
end

function show(io::IO, mime::MIME"text/plain", s::Symbol)
  print(io, string(s))
end

end # module
