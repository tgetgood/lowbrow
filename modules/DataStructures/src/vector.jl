abstract type Vector <: Sequential end


"""
N-ary (where N == nodelength) trees with values stored only in the leaves.

A PersistentVector is either empty, a complete tree, or all children but the
rightmost are complete trees. This invariant keeps the trees balanced, resulting
in log_{32}(N) lookup, append, and element update operations, both in time and
memory.

It also simplifies lookup.
"""
abstract type PersistentVector <: Vector end

struct EmptyVector <: PersistentVector
end

struct VectorLeaf{T} <: PersistentVector
  elements::Base.Vector{T}
end

# REVIEW: Play with setting nodelength on a per vector basis and set it based on
# the size of the leaf element type.
#
# Actually doing the math, it looks like for very large trees of i8s the savings
# would approach 18%. That's not all that much. Might be worth it in some
# specialised settings, but not a priority until one of those come up.

function vectorleaf(args::Base.Vector)
  if 0 === length(args)
    emptyvector
  else
    VectorLeaf(args)
  end
end

struct VectorNode <: PersistentVector
  elements::Base.Vector{PersistentVector}
  # FIXME: This shouldn't be fixed size, but memory indirection is killing me.
  count::UInt64
  # max depth is log(nodelength, typemax(typeof(count))). 4 bits would suffice.
  depth::UInt8
end

function vectornode(els::Base.Vector, count, depth)
  VectorNode(els, UInt64(count), UInt8(depth))
end

# function vectornode(els::VectorLeaf, count, depth)
#   vectornode(Tuple(els), count, depth)
# end

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

length(v::Vector) = count(v)

conj(v::Nothing, x) = vectorleaf([x])
conj(v::EmptyVector, x) = vectorleaf([x])

# function conj(v::VectorLeaf{T}, x::S) where {T, S <: T}
#   if completep(v)
#     vectornode([v, vectorleaf([x])], count(v) + 1, 2)
#   else
#     temp = copy(v.elements)
#     push!(temp, x)
#     vectorleaf(temp)
#   end
# end

function addtoleaf(v::VectorLeaf{T}, x::S) where {T, S}
  N = typejoin(S, T)
  temp::Base.Vector{N} = copy(v.elements)
  push!(temp, x)
  VectorLeaf{N}(temp)
end

function addtoleaf(v::VectorLeaf{T}, x::S) where {T, S <: T}
  temp = copy(v.elements)
  push!(temp, x)
  VectorLeaf{T}(temp)
end

function conj(v::VectorLeaf{T}, x::S) where {T, S}
  if completep(v)
    vectornode([v, vectorleaf([x])], count(v) + 1, 2)
  else
    addtoleaf(v, x)
  end
end

function sibling(x, depth)
  if depth == 1
    vectorleaf([x])
  else
    vectornode([sibling(x, depth - 1)], 1, depth)
  end
end

function join(els::Base.Vector, v::Vector)
  # REVIEW: These asserts *shouldn't* be necessary. Can I prove that?
  # @assert every(x -> depth(v) == depth(x), els)
  temp = copy(els)
  push!(temp, v)
  vectornode(temp, sum(count, els; init=0) + count(v), depth(v) + 1)
end

function join(v1::VectorNode, v2::VectorNode)
  # TODO: Wrap @assert so that it can be disabled in production.
  # @assert depth(v1) == depth(v2)
  vectornode([v1, v2], count(v1) + count(v2), depth(v1) + 1)
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
  v.elements[n]
end

"""
Returns the nth element (starting at 1) of vector v.
"""
function nth(v::VectorNode, n)
  # REVIEW: Cast to and from 0-indexing. Not pretty.
  (d, r) = divrem(n-1, nodelength^(depth(v) - 1))
  nth(v.elements[d+1], r+1)
end

function getindex(v::Vector, n)
  nth(v, n)
end

function assoc(v::EmptyVector, i, val)
  throw("Index out of bounds")
end

function assoc(v::VectorLeaf, i, val)
  temp = copy(v.elements)
  temp[i] = val
  vectorleaf(temp)
end

function assoc(v::VectorNode, i, val)
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
    emptyvector
  else
    VectorSeq(v.v, v.i + 1)
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
    sum(count, nodes; init = 0),
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

function printvec(io::IO, v)
  print(io, transduce(interpose("\n ") ∘ map(string), *, "", v))
end


function show(io::IO, mime::MIME"text/plain", v::Vector)
  print(io, string(count(v)) * "-element DataStructures.Vector: [\n ")

  # REVIEW: Why 65? Because it had to be something...
  if count(v) > 65
    printvec(io, take(32, v))
    print(io, "\n ...\n ")
    printvec(io, takelast(32, v))
  else
    printvec(io, v)
  end

  print(io, "\n]")
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

##### Equality

hash(v::VectorLeaf) = hash(v.elements)
hash(v::VectorNode) = hash(v.elements)

function Base.:(==)(x::VectorLeaf, y::VectorLeaf)
  x.elements == y.elements
end

function Base.:(==)(x::VectorNode, y::VectorNode)
  x.count === y.count &&
    x.depth === y.depth &&
    x.elements == y.elements
end

################################################################################
# Transients
################################################################################

# N.B.: I think it's a mistake to make transients subtypes of the types they
# mirror. We don't want to accidentally substitute a transient type for a
# persistent type.
abstract type Transient end

abstract type TransientVector <: Transient end

struct TransientVectorLeaf{T} <: TransientVector
  elements::Base.Vector{T}
  active::Ref{Bool}
  lock::ReentrantLock
end

struct TransientVectorNode <: TransientVector
  # TransientVectors and PersistentVectors share no supertype, but can share
  # nodes (if that part hasn't been changed yet).
  elements::Base.Vector{Any}
  active::Ref{Bool}
  lock::ReentrantLock
end

count(v::TransientVectorLeaf) = length(v.elements)
count(v::TransientVectorNode) = sum(count, v.elements; init=0)

depth(v::TransientVectorLeaf) = 1
depth(v::TransientVectorNode) = 1 + depth(v.elements[1])

function tvl(elements::Base.Vector{T}) where T
  TransientVectorLeaf{T}(elements, Ref(true), ReentrantLock())
end

tvn(elements) = TransientVectorLeaf(elements, Ref(true), ReentrantLock())

# REVIEW: Do we need an empty marker for transients?
transient!(v::EmptyVector) = tvl([])
transient!(v::VectorLeaf) = tvl(copy(v.elements))
transient!(v::VectorNode) = tvn(copy(v.elements))

function checktransience(v::TransientVector)
  if !v.active[]
    throw("Transient has been peristed. Aborting to prevent memory corruption.")
  end
end

function tlwrap(f, v::TransientVector)
  try
    lock(v.lock)
    checktransience(v)
    f()
  finally
    unlock(v.lock)
  end
end

function persist!(v::TransientVectorLeaf)
  tlwrap(v) do
    v.active[] = false
    vectorleaf(v.elements)
  end
end

function addtoleaf(v::TransientVectorLeaf{T}, x::S) where {T, S}
  N = typejoin(S, T)
  v = tvl{N}(copy(v.elements))
  push!(v.elements, x)
  return v
end

function addtoleaf(v::TransientVectorLeaf{T}, x::S) where {T, S <: T}
  push!(v.elements, x)
  return v
end

function conj!(v::TransientVectorLeaf{T}, x::S) where {T, S <: T}
  if length(v.elements) == nodelength
    tvn([v, tvl([x])])
  else
    addtoleaf(v, x)
  end
end

function conj!(v::TransientVectorNode, x)
end
