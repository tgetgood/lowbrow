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

vl(v::Base.Vector) = VectorLeaf(v)
vl(t::Tuple) = VectorLeaf([x for x in t])
vl(x) = VectorLeaf(convert(Base.Vector, x))

function vectorleaf(args)
  if 0 === length(args)
    emptyvector
  else
    vl(args)
  end
end

struct VectorNode{T} <: PersistentVector where T <: PersistentVector
  elements::Base.Vector{T}
  # FIXME: This shouldn't be fixed size, but memory indirection is killing me.
  count::Int64
  # max depth is log(nodelength, typemax(typeof(count))). 4 bits would suffice.
  # But, due to alignment using u8 saves no space and creates extra work.
  depth::Int64
end

function vectornode(els::Base.Vector, count, depth)
  VectorNode(els, count, depth)
end

function vectornode(els::Base.Vector)
  VectorNode(els, sum(count, els; init=0), depth(els[1]) + 1)
end

function ireduce(f, init, coll::VectorLeaf)
  Base.reduce(f, coll.elements, init=init)
end

function ireduce(f, init, coll::VectorNode)
  Base.reduce(
    (acc, x) -> ireduce(f, acc, x),
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
# actually know though. Recursive type calculation can't be good for you though.
eltype(v::VectorLeaf{T}) where T = T

function eltype(v::VectorNode{T}) where T
  S = T
  try
    while length(S.parameters) > 0
      S = S.parameters[1]
    end
    S
  catch e
    Any
  end
end

const emptyvector = EmptyVector()

empty(x::Vector) = emptyvector

count(v::VectorLeaf) = length(v.elements)
count(v::VectorNode) = v.count
count(v::EmptyVector) = 0

length(v::Vector) = count(v)

conj(v::Nothing, x) = vectorleaf([x])
conj(v::EmptyVector, x) = vectorleaf([x])
conj(c::EmptyVector, x::NoEmission) = c

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

function join(els::Base.Vector{T}, v::T) where T <: PersistentVector
  temp = copy(els)
  push!(temp, v)
  vectornode(temp, sum(count, els; init=0) + count(v), depth(v) + 1)
end

function join(els::Base.Vector, v::Vector)
  temp::Base.Vector{typejoin(eltype(els), eltype(v))} = copy(els)
  push!(temp, v)
  vectornode(temp, sum(count, els; init=0) + count(v), depth(v) + 1)
end

function join(v1::VectorNode, v2::VectorNode)
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
vector(a) = vectorleaf([a])
vector(a,b) = vectorleaf([a,b])
vector(a,b,c) = vectorleaf([a,b,c])
vector(a,b,c,d) = vectorleaf([a,b,c,d])

vec() = emptyvector
vec(v::Vector) = v

# REVIEW: We could have a vector where one leaf contains UInt16s, another
# contains float32s, etc.. Alignment would be a kind of magic and not practical
# for most applications.
#
# jl tries very hard to make array elements homogenous bits types. The benefits
# are obvious.
#
# But what if we allowed the length of leaves to vary and ensured each leaf was
# a vector of homogenous bits type?
#
# Would that ever be useful in real life? I haven't come across that need, so
# these vectors are still fully homogeneous (though possibly not just bits types
# since we use `typejoin` when needed.
#
# But so far, for my purposes, a vector is either homogeneous
# ints/floats/etc. or effectively Any.
#
# It *might* be useful to be more granular in joining types since right now if
# you add a UInt16 to a vector of UInt32s it boxes everything instead of padding
# the UInt16. Again, I don't need this yet.

function leafpartition(; init=[])
  acc::Ref{Any} = 0
  i = length(init)
  if i > 0
    t = Base.Vector{eltype(init)}(undef, nodelength)
    for j in 1:i
      t[j] = init[j]
    end
    acc[] = t
  end
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      if acc[] !== 0 && i > 0
        emit(emit(result, [acc[][j] for j in 1:i]))
      else
        emit(result)
      end
    end
    function inner(result, next)
      if acc[] === 0
        t = Base.Vector{typeof(next)}(undef, nodelength)
        acc[] = t
      end
      i += 1
      try
        acc[][i] = next
      catch e
        # One strike and you're boxed
        if e isa MethodError && e.f == convert

          # TODO: Performance warnings flag and macro. Sometimes you just need
          # reflection and don't want to get swamped with warnings.
          @warn "Heterogeneous type, boxing values."

          t = Base.Vector{Any}(undef, nodelength)
          for j in 1:i-1
            t[j] = acc[][j]
          end
          t[i] = next
          acc[] = t
        else
          throw(e)
        end
      end
      if nodelength === i
        i = 0
        emit(result, copy(acc[]))
      else
        result
      end
    end
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
  if length(args) <= nodelength
    vectorleaf(args)
  else
    intoemptyvec(identity, args)
  end
end

# function vecbuilder(xform, to, from)
#   T = typejoin(eltype(to), eltype(from))



# end

# function into(x::EmptyVector, xform, from)
#   intoemptyvec(xform, from)
# end

# function into(x::EmptyVector, T, from)
#   intoemptyvec(identity, from)
# end


function intoemptyvec(xform, args)

  xf = [leafpartition(), map(vectorleaf)]

  for i = 2:ceil(log(nodelength, length(args)))
    append!(xf, [leafpartition(), map(incompletevectornode)])
  end

  # REVIEW: We ought to be able to do type inference via the composed chain of
  # transforms. That seems like a lot of work though.
  transduce(∘(xform, xf...), lastarg, nil, args)
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

function show(io::IO, mime::MIME"text/plain", v::EmptyVector)
  print(io, "[]")
end

function show(io::IO, mime::MIME"text/plain", v::Vector)
  print(io, string(count(v)) * "-element DataStructures.Vector: [\n ")

  # REVIEW: Why 33? Because it had to be something...
  if count(v) > 33
    printvec(io, take(16, v))
    print(io, "\n ...\n ")
    printvec(io, takelast(16, v))
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

# FIXME: Hashing the type is not stable between runs. Not critical just yet,
# but it will be. I want hashes to be sufficiently stable that they can go on
# the wire. Basically hash values and never hash memory addresses.
hash(v::T) where T <: PersistentVector = xor(hash(T), hash(v.elements))

function Base.:(==)(x::VectorLeaf, y::VectorLeaf)
  x.elements == y.elements
end

function Base.:(==)(x::VectorNode, y::VectorNode)
  x.count === y.count && x.elements == y.elements
end

function Base.convert(::Type{Base.Vector{T}}, xs::VectorLeaf{T}) where T
  copy(xs.elements)
end

function Base.convert(::Type{Base.Vector{T}}, xs::VectorNode) where T
  v = Base.Vector{T}()
  dumpwalk(v, xs)
end

function dumpwalk(x::Base.Vector{T}, v::VectorNode) where T
  reduce(dumpwalk, x, v.elements)
end

function dumpwalk(x::Base.Vector{T}, v::VectorLeaf{T}) where T
  append!(x, v.elements)
end
