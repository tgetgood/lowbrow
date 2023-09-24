abstract type Vector <: Sequential end

abstract type Transient end
"""
N.B.: I think it's a mistake to make transients subtypes of the types the
mirror. We don't want to accidentally substitute a transient type for a
persistent type.
"""
abstract type TransientVector <: Transient end

struct TransientVectorLeaf <: TransientVector
  elements::Base.Vector
end

struct TransientVectorNode <: TransientVector
end

"""
N-ary (where N == nodelength) trees with values stored only in the leaves.

A PersistentVector is either empty, a complete tree, or all children but the
rightmost are complete trees. This invariant keeps the trees balanced, resulting
in log_{32}(N) lookup, append, and element update operations, both in time and
memory.

It also lets us statically calculate the lookup path for a given index, which
could theoretically lead to constant time lookup if the compiler can inline
nodes. I don't know that it can, but it doesn't seem impossible if the element
types are well behaved.
"""
abstract type PersistentVector <: Vector end

struct EmptyVector <: PersistentVector
end

struct VectorLeaf <: PersistentVector
  elements::Tuple
end

# Tuple calls convert when passed a Tuple... Why is that?
vectorleaf(args::Tuple) = VectorLeaf(args)
vectorleaf(args) = VectorLeaf(Tuple(args))

struct VectorNode{N} <: PersistentVector
  elements::Union{NTuple{N, VectorLeaf}, NTuple{N, VectorNode}}
  # FIXME: This shouldn't be fixed size, but memory indirection is killing me.
  count::UInt64
  # max depth is log(nodelength, typemax(typeof(count))). 4 bits would suffice.
  depth::UInt8
end

function vectornode(els::Tuple, count, depth)
  VectorNode(els, UInt64(count), UInt8(depth))
end

function vectornode(els, count, depth)
  vectornode(Tuple(els), count, depth)
end

function reduce(f, init, coll::VectorLeaf)
  Base.reduce(f, coll.elements, init=init)
end

function reduce(f, init, coll::VectorNode)
  Base.reduce(
    (acc, x) -> reduce(f, acc, x),
    coll.elements,
    init=init
  )
end

depth(x::Nothing) = 0
depth(v::EmptyVector) = 0
depth(v::VectorLeaf) = 1
depth(v::VectorNode) = v.depth

emptyp(v::EmptyVector) = true
emptyp(v::PersistentVector) = false

completep(v::EmptyVector) = true
completep(v::VectorLeaf) = count(v) == nodelength

function completep(v::VectorNode)
  count(v) == nodelength^v.depth
end

# If a vector is homogeneous, this may help with code generation. I don't
# actually know though
function eltype(v::VectorLeaf)
  eltype(v.elements)
end

const emptyvector = EmptyVector()

empty(x::Vector) = emptyvector

count(v::VectorLeaf) = length(v.elements)
count(v::VectorNode) = v.count
count(v::EmptyVector) = 0

function length(v::Vector)
  count(v)
end

function conj(v::EmptyVector, x)
  vectorleaf((x,))
end

function conj(v::VectorLeaf, x)
  if completep(v)
    vectornode((v, vectorleaf((x,))), count(v) + 1, 2)
  else
    vectorleaf((v.elements..., x))
  end
end

function sibling(x, depth)
  if depth == 1
    vectorleaf((x,))
  else
    vectornode(tuple(sibling(x, depth - 1)), 1, depth)
  end
end

function join(els::NTuple, v::Vector)
  @assert every(x -> depth(v) == depth(x), els)
  vectornode((els..., v), sum(map(count, els); init=0) + count(v), depth(v) + 1)
end

function join(v1::VectorNode, v2::VectorNode)
  @assert depth(v1) == depth(v2)
  vectornode((v1, v2), count(v1) + count(v2), depth(v1) + 1)
end

function conj(v::VectorNode, x)
  if completep(v)
    join(v, sibling(x, depth(v)))
  elseif completep(v.elements[end])
    join(v.elements, sibling(x, depth(v) - 1))
  else
    join(v.elements[1:end-1], conj(v.elements[end], x))
  end
end

last(v::VectorLeaf) = v.elements[end]
last(v::VectorNode) = last(v.elements[end])
last(v::EmptyVector) = nothing

first(v::EmptyVector) = nothing
first(v::VectorLeaf) = v.elements[begin]
first(v::VectorNode) = first(v.elements[begin])

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

function getindex(v::Vector, n)
  nth(v, n)
end

function assoc(v::EmptyVector, i, val)
  throw("Index out of bounds")
end

function assoc(v::VectorLeaf, i, val)
  @assert 1 <= i && i <= count(v) "Index out of bounds"

  return VectorLeaf((v.elements[begin:i-1]..., val, v.elements[i+1:end]...))
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

function rest(v::Vector)
  if count(v) <= 1
    emptyvector
  else
    VectorSeq(v, 2)
  end
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

get(v::Vector, i) = nth(v, i)

vector(args...) = vec(args)
vector() = emptyvector

vec() = emptyvector
vec(v::Vector) = v

function leafpartition()
  acc = []
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      if count(acc) > 0
        emit(emit(result, acc))
      else
        emit(result)
      end
    end
    function inner(result, next)
      push!(acc, next)
      if length(acc) == nodelength
        t = acc
        acc = []
        emit(result, t)
      else
        result
      end
    end
    return inner
  end
end

function incompletevectornode(nodes)
   vectornode(
    nodes,
    sum(map(count, nodes); init = 0),
    depth(nodes[1]) + 1
  )
end

function vec(args)
  xf = [leafpartition(), map(vectorleaf)]

  for i = 2:ceil(log(nodelength, length(args)))
    append!(xf, [leafpartition(), map(incompletevectornode)])
  end

  first(into(emptyvector, ∘(xf...) , args))
end

reverse(v::EmptyVector) = v

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

function takelast(n, v::Vector)
  c = count(v)
  if n >= c
    v
  else
    into(emptyvector, map(i -> nth(v, i)), c-n+1:c)
  end
end

function show(io::IO, mime::MIME"text/plain", v::Vector)
  # REVIEW: Why 65? Because it had to be something...
  if count(v) > 65
    elements =
      transduce(interpose("\n ") ∘ map(string), *, "", take(32, v)) *
      "\n ...\n " *
      transduce(interpose("\n ") ∘ map(string), *, "", takelast(32, v))
  else
    elements = transduce(interpose("\n ") ∘ map(string), *, "", v)
  end

  str = string(count(v)) * "-element DataStructures.Vector:\n " * elements
  print(io, str)
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
