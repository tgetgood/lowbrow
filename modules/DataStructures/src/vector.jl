abstract type Vector <: Sequential end

abstract type PersistentVector <: Vector end

struct VectorLeaf <: PersistentVector
  elements::Tuple
end

Base.convert(::Type{Base.Vector}, xs::VectorLeaf) = xs.elements

struct VectorNode{N} <: PersistentVector
  elements::NTuple{N, PersistentVector}
  count::Unsigned
end

function eltype(v::VectorLeaf)
  eltype(v.elements)
end

struct EmptyVector <: PersistentVector
end

const emptyvector = EmptyVector()

function empty(x::Vector)
  emptyvector
end

function empty(x::Base.Vector)
  []
end

function count(v::Base.Vector)
  length(v)
end

function count(v::VectorLeaf)
  length(v.elements)
end

function count(v::VectorNode)
  v.count
end

function count(v::EmptyVector)
  0
end

function length(v::Vector)
  count(v)
end

function fullp(v::VectorLeaf)
  count(v) >= nodelength
end

function fullp(v::VectorNode)
  count(v.elements) >= nodelength && fullp(v.elements[end])
end

""" Returns `true` iff the collection `x` contains no elements. """
function emptyp(x::Sequential)
  count(x) == 0
end

function emptyp(x)
  length(x) == 0
end

function conj(v::Base.Vector, x)
  vcat(v, [x])
end

function conj(v::EmptyVector, x)
  VectorLeaf((x,))
end

function conj(v::VectorLeaf, x)
  if fullp(v)
    VectorNode((v, VectorLeaf((x,))), UInt(count(v) + 1))
  else
    VectorLeaf(tuple(v.elements..., x))
  end
end

function conj(v::VectorNode, x)
  c = UInt(v.count + 1)
  if fullp(v)
    VectorNode((v, VectorLeaf((x,))), c)
  elseif fullp(v.elements[end])
    VectorNode(tuple(v.elements..., VectorLeaf((x,))), c)
  else
    VectorNode(tuple(v.elements[begin:end-1]..., conj(tail, x)), c)
  end
end

function last(v::VectorLeaf)
  v.elements[end]
end

function last(v::VectorNode)
  last(v.elements[end])
end

function last(v::EmptyVector)
  nothing
end

function first(v::EmptyVector)
  nothing
end

function first(v::VectorLeaf)
  if count(v) > 0
    v.elements[begin]
  else
    nothing
  end
end

function first(v::VectorNode)
  if count(v) > 0
    first(v.elements[begin])
  else
    nothing
  end
end

function getindex(v::Vector, n)
  nth(v, n)
end

function nth(v::VectorLeaf, n)
  if n > count(v) || n < 1
    throw("Index out of bounds")
  else
    return v.elements[n]
  end
end

"""
Returns the nth element (starting at 1) of vector v.
"""
function nth(v::VectorNode, n)
  if n > count(v) || n < 1
    throw("Index out of bounds")
  else
    # FIXME: This should be binary search.
    for e in v.elements
      if count(e) >= n
        return nth(e, n)
      else
        n = n - count(e)
      end
    end
  end
end

function assoc(v::Base.Vector, i, val)
  v2 = copy(v)
  v2[i] = val
  return v2
end

function assoc(v::EmptyVector, i, val)
  @assert false "Index out of bounds"
end

function assoc(v::VectorLeaf, i, val)
  @assert 1 <= i && i <= count(v) "Index out of bounds"

  return VectorLeaf(tuple(v.elements[begin:i-1]..., val, v.elements[i+1:end]...))
end

function assoc(v::VectorNode, i, val)
  @assert 1 <= i && i <= count(v) "Index out of bounds"

  @assert false "Not implemented"
end

function zip(v1::Vector, v2::Vector)
  v = emptyvector
  for i = 1:min(count(v1), count(v2))
    v = conj(v, vector(nth(v1, i), nth(v2, i)))
  end
  return v
end

# FIXME: This method of iterating a vector doesn't allow the head to be
# collected and so will use more memory than expected when used in idiomatic
# lisp fashion. That should be fixed.
struct VectorSeq <: Vector
  v::Vector
  i
end

function count(v::VectorSeq)
  count(v.v) - v.i + 1
end

function seq(v::Vector)
  VectorSeq(v, 1)
end

function rest(v::Base.Vector)
  v[2:end]
end

function rest(v::Vector)
  if count(v) <= 1
    return emptyvector
  else
    return VectorSeq(v, 2)
  end
end

function rest(v::UnitRange)
  rest(Base.Vector(v))
end

function first(v::VectorSeq)
  nth(v.v, v.i)
end

function rest(v::VectorSeq)
  if v.i == count(v.v)
    return emptyvector
  else
    return VectorSeq(v.v, v.i + 1)
  end
end

function string(v::VectorSeq)
  "[" * transduce(map(string) ∘ interpose(" "), *, "", v) * "]"
end

function get(v::Vector, i)
  nth(v, i)
end

function get(v::Base.Vector, i)
  if isdefined(v, Int(i))
    v[i]
  else
    nothing
  end
end

function reduce(f, init::Vector, coll::VectorLeaf)
  Base.reduce(f, coll.elements, init=init)
end

function reduce(f, init::Vector, coll::VectorNode)
  Base.reduce(
    (acc, x) -> reduce(f, acc, x),
    coll.elements,
    init=init
  )
end

function vector(args...)
  vec(args)
end

function vec(args)
  Base.reduce(conj, args, init=emptyvector)
end

function vec(v::Vector)
  v
end

function reverse(v::EmptyVector)
  v
end

function reverse(v::Vector)
  r = emptyvector
  for i = count(v):-1:1
    r = conj(r, nth(v, i))
  end
  r
end

function string(v::Vector)
  "[" * transduce(interpose(" ") ∘ map(string), *, "", v) * "]"
end

function iterate(v::Vector)
  first(v), rest(v)
end

function iterate(v::Vector, state)
  if count(state) == 0
    nothing
  else
    first(state), rest(state)
  end
end
