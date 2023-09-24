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

rest(v::Base.Vector) = v[2:end]
rest(v::UnitRange) = rest(Base.Vector(v))

function get(v::Base.Vector, i)
  if isdefined(v, Int(i))
    v[i]
  else
    nothing
  end
end

Base.convert(::Type{Base.Vector}, xs::VectorLeaf) = [i for i in xs.elements]
Base.convert(::Type{Vector}, xs::Tuple) = vec(xs)
Base.convert(::Type{Vector}, xs::Base.Vector) = vec(xs)
Base.convert(::Type{Vector}, xs::UnitRange) = vec(xs)
