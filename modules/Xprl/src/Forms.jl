module Forms

import Base: show, string, hash, ==, getindex, lastindex, iterate

import DataStructures as ds

abstract type Form end

function show(io::IO, mime::MIME"text/plain", s::Form)
  print(io, string(s))
end

struct ListForm <: Form
  elements::Vector
end

function getindex(v::ListForm, n)
  v.elements[n]
end

function lastindex(v::ListForm)
  lastindex(v.elements)
end

function iterate(v::ListForm)
  v.elements[1], v.elements[2:end]
end

function string(f::ListForm)
  "(" * ds.into("", ds.map(string) ∘ ds.interpose(" "), f.elements) * ")"
end

struct ValueForm <: Form
  content::Any
end

function show(io::IO, mime::MIME"text/plain", s::ValueForm)
  show(io, s.content)
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

abstract type  Immediate <: Form end

struct ImmediateSymbol <: Immediate
  content::Symbol
end

struct ImmediateList <: Immediate
  content::ListForm
end

struct ImmediateImmediate <: Immediate
  content::Immediate
end

string(f::Immediate) = "~"*string(f.content)

end # module
