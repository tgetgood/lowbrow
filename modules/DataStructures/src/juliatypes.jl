# Extensions of methods to jl native types

# Ranges are immutable, so let's just use our vectors.
empty(x::AbstractRange) = emptyvector
empty(x::Base.Vector) = []

count(v::Base.Vector) = length(v)
count(xs::Tuple) = length(xs)

conj(v::Base.Vector, x) = vcat(v, [x])

rest(v::Base.Array) = v[2:end]
rest(v::UnitRange) = rest(Base.Vector(v))
rest(v::Tuple) = v[2:end]

conj(m::Map, v::Base.Vector) = assoc(m, v[1], v[2])
conj(m::Map, e::NTuple{2, Any}) = assoc(m, e[1], e[2])

function get(v::Base.Vector, i)
  if isdefined(v, Int(i))
    v[i]
  else
    nothing
  end
end

ireduce(f, init, coll::AbstractRange) = Base.reduce(f, coll; init)
ireduce(f, init, coll::Array) = Base.reduce(f, coll; init)
ireduce(f, init, coll::Tuple) = Base.reduce(f, coll; init)


Base.convert(::Type{Base.Vector}, xs::VectorLeaf) = [i for i in xs.elements]
Base.convert(::Type{Vector}, xs::Tuple) = vec(xs)
Base.convert(::Type{Vector}, xs::Base.Vector) = vec(xs)
Base.convert(::Type{Vector}, xs::UnitRange) = vec(xs)
