module Forms

import Base: show, string

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

function string(s::Symbol)
  ds.into("", ds.map(string) ∘ ds.interpose("."), s.name.names)
end

function show(io::IO, mime::MIME"text/plain", s::Symbol)
  print(io, string(s))
end

end # module
