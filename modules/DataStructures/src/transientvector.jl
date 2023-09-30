# N.B.: I think it's a mistake to make transients subtypes of the types they
# mirror. We don't want to accidentally substitute a transient type for a
# persistent type.
abstract type Transient end

abstract type TransientVector <: Transient end

struct TransientVectorLeaf{T} <: TransientVector
  elements::Base.Vector{T}
  lock::ReentrantLock
  active::Ref{Bool}
end

struct TransientVectorNode <: TransientVector
  # TransientVectors and PersistentVectors share no supertype, but can share
  # nodes (if that part hasn't been changed yet).
  elements::Base.Vector{Any}
  lock::ReentrantLock
  depth::UInt8
  active::Ref{Bool}
end

# Effective type inference requires an empty marker here.
struct TransientEmptyVector <: TransientVector end

count(v::TransientEmptyVector) = 0
count(v::TransientVectorLeaf) = length(v.elements)
count(v::TransientVectorNode) = sum(count, v.elements; init = 0)

depth(v::TransientEmptyVector) = 0
depth(v::TransientVectorLeaf) = 1
depth(v::TransientVectorNode) = v.depth

const transientemptyvector = TransientEmptyVector()

function tvl(elements::Base.Vector{T}) where T
  TransientVectorLeaf{T}(elements, ReentrantLock(), Ref(true))
end

function tvn(elements)
  TransientVectorNode(
    elements,
    ReentrantLock(),
    UInt8(depth(elements[1]) + 1),
    Ref(true)
  )
end

# REVIEW: Do we need an empty marker for transients?
transient!(v::EmptyVector) = transientemptyvector
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

function unsafepersist!(v::PersistentVector)
  v
end

function unsafepersist!(v::TransientVectorLeaf)
  v.active[] = false
  vectorleaf(v.elements)
end

function unsafepersist!(v::TransientVectorNode)
  v.active[] = false
  vectornode(map(unsafepersist!, v.elements))
end

function persist!(v::TransientEmptyVector)
  emptyvector
end

function persist!(v::TransientVector)
  tlwrap(v) do
    # a node holds the only references to its children, so unless something very
    # off is happening, we only need to acquire the lock for the root of the
    # tree.
    unsafepersist!(v)
  end
end

function conj!(v::TransientEmptyVector, x)
  tvl([x])
end

function addtoleaf!(v::TransientVectorLeaf{T}, x::S) where {T, S}
  N = typejoin(S, T)
  res = tvl{N}(copy(v.elements))
  push!(res.elements, x)
  return res
end

function addtoleaf!(v::TransientVectorLeaf{T}, x::S) where {T, S <: T}
  push!(v.elements, x)
  return v
end

function conj!(v::TransientVectorLeaf{T}, x::S) where {T, S <: T}
  tlwrap(v) do
    if length(v.elements) == nodelength
      tvn([v, tvl([x])])
    else
      addtoleaf!(v, x)
    end
  end
end

function tryconj!(v::TransientVectorLeaf{T}, x::S) where {T, S}
  if length(v.elements) < nodelength
    :set, conj!(v, x)
  else
    :failure, nil
  end
end

function tryconj!(v::TransientVectorLeaf{T}, x::S) where {T, S <: T}
  if length(v.elements) < nodelength
    conj!(v, x)
    :success, nil
  else
    :failure, nil
  end
end

function transientsibling(x, depth)
  if depth == 1
    tvl([x])
  else
    tvn([transientsibling(x, depth - 1)])
  end
end

function tryconj!(v::VectorLeaf, x)
  :set, conj!(transient!(v), x)
end

function tryconj!(v::VectorNode, x)
  :set, conj!(transient!(v), x)
end

function tryconj!(v::TransientVectorNode, x)
  (status, el) = tryconj!(v.elements[end], x)
  if status === :success
    status, nil
  elseif status === :set
    v.elements[end] = el
    :success, nil
  elseif length(v.elements) < nodelength
    push!(v.elements, transientsibling(x, depth(v)))
    :success, nil
  else
    :failure, nil
  end
end

function conj!(v::TransientVectorNode, x)
  tlwrap(v) do
    (status, el) = tryconj!(v.elements[end], x)
    if status === :success
      v
    else
      tvn([v, transientsibling(x, depth(v))])
    end
  end
end
