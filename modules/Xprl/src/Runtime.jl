module Runtime

import Base: hash, ==

import DataStructures as ds

"""
Represents an application of args to a function-like entity which has not been
performed yet.
"""
struct Application
  head
  tail
end

function Base.:(==)(x::Application, y::Application)
  x.head == y.head && x.tail == y.tail
end

const apphash = hash("#Application")

function hash(x::Application)
  xor(apphash, hash(x.head), hash(x.tail))
end

struct Mu
  argsym
  body
end

function Base.:(==)(x::Mu, y::Mu)
  x.argsym == y.argsym && x.body == y.body
end
const muhash = hash("#Mu")

function hash(x::Mu)
  xor(muhash, hash(x.argsym), hash(x.body))
end

end # module
