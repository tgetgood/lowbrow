# Extensions of methods to jl native types (mostly Base.Vector)

empty(x::Base.Vector) = []

count(v::Base.Vector) = length(v)

conj(v::Base.Vector, x) = vcat(v, [x])

function assoc(v::Base.Vector, i, val)
  @warn "assoc on Base.Vector is copy-on-write"
  v2 = copy(v)
  v2[i] = val
  return v2
end

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

reduce(f, init, coll::UnitRange) = Base.reduce(f, coll; init)
reduce(f, init, coll::Array) = Base.reduce(f, coll; init)
reduce(f, init, coll::Tuple) = Base.reduce(f, coll; init)


Base.convert(::Type{Base.Vector}, xs::VectorLeaf) = [i for i in xs.elements]
Base.convert(::Type{Vector}, xs::Tuple) = vec(xs)
Base.convert(::Type{Vector}, xs::Base.Vector) = vec(xs)
Base.convert(::Type{Vector}, xs::UnitRange) = vec(xs)
