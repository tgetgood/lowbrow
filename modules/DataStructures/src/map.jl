abstract type Map <: Sequential end

abstract type MapNode end

# REVIEW: Would adding {K,V} type parameters do anything except bloat code size?
struct MapEntry <: MapNode
  key::Any
  value::Any
end

function key(x::MapEntry)
  x.key
end

function val(x::MapEntry)
  x.value
end

function Base.:(==)(x::MapEntry, y::MapEntry)
  x.key == y.key && x.value == y.value
end

struct EmptyMap <: Map end

const emptymap = EmptyMap()

# Clojure uses 8 and I don't want to dig into it just yet.
# TODO: Analysis
const arraymapsizethreashold = 8

struct PersistentArrayMap <: Map
  kvs::Base.Vector{Any}
end

struct EmptyMarker <: MapNode end

const emptymarker = EmptyMarker()

# N.B.: It's important that nodes not be maps themselves since nodes with
# different levels cannot be merged sensibly and so passing subnodes around as
# full fledged maps is bound to end in confusion and disaster.
struct PersistentHashNode <: MapNode
  ht::Base.Vector{MapNode}
  # FIXME: Should not be fixed size
  level::Int
  count::Int
end

const emptyhash::Base.Vector{MapNode} = [emptymarker for i in 1:nodelength]

emptyhashnode(level) = PersistentHashNode(emptyhash, level, 0)

# REVIEW: One extra memory indirection makes all the ensuing code cleaner. I'll
# consider it worth it until proven otherwise.
struct PersistentHashMap <: Map
  root::PersistentHashNode
end

const emptyhashmap = PersistentHashMap(emptyhashnode(1))

struct HashSeq
  hash
  current
end

"""Returns a seq of chunks of `hashbits` bits.
Should be an infinite seq, but in the present implementation runs out after 64
bits."""
hashseq(x) = HashSeq(hash(x), 1)

function first(s::HashSeq)
  if s.current > 14
    # We could return nothing, but that will just lead to an error when it's
    # used which will be hard to debug unless I remember this...
    throw("FIXME: hash streams not implemented")
  else
    s.hash << ((s.current - 1) * hashbits) >> (64 - hashbits)
  end
end

rest(s::HashSeq) = HashSeq(s.hash, s.current + 1)

# This is a kludge. These hashes need to be cached somehow or they'll kill all
# hope of performance.
nth(h::HashSeq, n) = first(HashSeq(h.hash, h.current+n))

##### General methods

# REVIEW: This might be a tad slow for large maps. At least it's cacheable (and
# incremental!). But then how do I make use of that?
function hash(m::Map)
  # 0xd45866ec3759ca93 is a random seed. I want any two maps with the same
  # elements to have the same hash and be equal. This seems like a decent way to
  # accomplish that.
  transduce(map(hash), xor, 0xd45866ec3759ca93, m)
end

empty(m::Map) = emptymap

count(m::EmptyMarker) = 0
count(m::PersistentHashNode) = m.count
count(m::MapEntry) = 1
count(m::EmptyMap) = 0
count(m::PersistentArrayMap) = div(length(m.kvs), 2) # inline kvs
count(m::PersistentHashMap) = m.root.count # REVIEW: Too much indirection?

emptyp(m::Map) = count(m) == 0

conj(m::Map, v::Vector) = assoc(m, v[1], v[2])

assoc(m::Map, k::Nothing, v) = throw("nothing is not a valid map key.")

first(m::Map) = first(seq(m))
rest(m::Map) = rest(seq(m))

get(m::Map, k, default=nil) = getindexed(m, k, default)[1]

conj(m::Map, x::Nothing) = m

function getin(m::Map, ks, default=nil)
  (v, i) = getindexed(m, first(ks))
  if i === :notfound
    default
  elseif count(ks) == 1
    v
  else
    getin(v, rest(ks), default)
  end
end

containsp(m::Map, k) = getindexed(m, k)[2] !== :notfound

function associn(m::Map, ks, v)
  if count(ks) == 1
    assoc(m, first(ks), v)
  else
    k = first(ks)
    assoc(m, k, associn(get(m, k, emptymap), rest(ks), v))
  end
end

function assoc(m::Map, k, v, kvs...)
  @assert length(kvs) % 2 == 0

  into(assoc(m, k, v), partition(2), kvs)
end

merge(x::Map) = x

function update(m, k, f, v...)
  nv = f(get(m, k), v...)
  assoc(m, k, nv)
end

function updatein(m, ks, f, v...)
  k = first(ks)
  if emptyp(rest(ks))
    update(m, k, f, v...)
  else
    nv =  updatein(get(m, k), rest(ks), f, v...)
    assoc(m, k, nv)
  end
end

function hashmap(args...)
  @assert length(args) % 2 == 0
  into(emptymap, partition(2), args)
end

function string(x::MapEntry)
  string(x.key) * ": " * string(x.value)
end

function showrecur(io::IO, depth, e::MapEntry)
  showrecur(io, depth, e.key)
  print(io, " -> ")
  showrecur(io, depth, e.value)
end

function string(m::Map)
  inner = transduce(
    map(string) ∘ interpose(", "),
    *,
    "",
    m
  )
  return "{" * inner * "}"
end

function showrecur(io::IO, depth, m::EmptyMap)
  print(io, "{}")
end

function aligncol(io::IO, depth, es)
  len = max(map(length ∘ string ∘ key, es)...) + 2
  for i in 1:length(es)
    if i > 1
      indent(io, depth-1)
      print(io, " ")
    end

    k = key(es[i])
    if isa(k, Sequential)
      showrecur(io, depth, k)
    else
      s = string(k)
      print(io, s)
      print(io, repeat(" ", len - length(s)))
    end
    showrecur(io, depth, val(es[i]))

    if i != length(es)
      print(io, "\n")
    end
  end
end

function showrecur(io::IO, depth, m::Map)
  print(io, "{")

  s = seq(m)
  if count(m) > 33
    aligncol(io, depth, take(16, s))
    print(io, "\n ...\n")
    indent(io, depth)
    aligncol(io, depth, drop(count(m) - 16, s))
  else
    aligncol(io, depth, s)
  end
  print(io, "}")
end

function show(io::IO, mime::MIME"text/plain", s::Map)
  showrecur(io, 1, s)
end

function keys(m::Map)
  map(x -> x.key, seq(m))
end

function vals(m::Map)
  map(x -> x.value, seq(m))
end

function zipmap(x, y)
  reduce(assoc, emptymap, x, y)
end

## FIXME: Sooo much boilerplate. I need to write macros for building xforms.
function mapkeys(f)
  function emit()
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, e)
      emit(result, MapEntry(f(key(e)), val(e)))
    end
  end
end

function mapvals(f)
  function emit()
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, e)
      emit(result, MapEntry(key(e), f(val(e))))
    end
  end
end

mapkeys(f, m) = into(empty(m), mapkeys(f), m)
mapvals(f, m) = into(empty(m), mapvals(f), m)

##### Empty maps

merge(x::EmptyMap, y::Map) = y
merge(x::Map, y::EmptyMap) = x

merge(x::Nothing, y::Map) = y
merge(x::Map, y::Nothing) = x

assoc(x::Nothing, k::Nothing, v) = throw("nothing is not a valid map key.")
assoc(x::Nothing, k, v) = PersistentArrayMap([k, v])
assoc(m::EmptyMap, k, v) = PersistentArrayMap([k, v])

conj(m::EmptyMap, e::MapEntry) = assoc(m, key(e), val(e))

get(m::Nothing, k) = nil
get(m::Nothing, k, default) = default
get(m::EmptyMap, x) = nil
get(m::EmptyMap, x, default) = default

seq(x::Nothing) = emptyvector
seq(x::EmptyMap) = emptyvector

function getindexed(m::EmptyMap, k)
  nothing, :notfound
end

function Base.:(==)(x::EmptyMap, y::Map)
  count(y) === 0
end

function Base.:(==)(x::Map, y::EmptyMap)
  count(x) === 0
end

##### Array Maps

first(m::PersistentArrayMap) = MapEntry(m.kvs[1], m.kvs[2])

"""
Returns (v, i) where `v` is the value associated with key `k` in `m` and `i` is
an index of `k` in `m` (what that means depends on the concrete type of `m`).

i == :notfound if k is not a key in m.
"""
function getindexed(m::PersistentArrayMap, k, default=nil)
  i = 1
  while i < length(m.kvs)
    if m.kvs[i] == k
      return m.kvs[i+1], i
    end
    i += 2
  end
  return default, :notfound
end

function conj(m::PersistentArrayMap, e::MapEntry)
  assoc(m, e.key, e.value)
end

function assoc(m::PersistentArrayMap, k, v)
  (_, i) = getindexed(m, k)
  if i === :notfound
    if count(m) >= arraymapsizethreashold
      assoc(into(emptyhashmap, m), k, v)
    else
      PersistentArrayMap(push!(copy(m.kvs), k, v))
    end
  else
    kvs = []
    append!(kvs, m.kvs[1:i-1], m.kvs[i+2:end])
    push!(kvs, k, v)
    PersistentArrayMap(kvs)
  end
end

function dissoc(m::PersistentArrayMap, k)
  (_, i) = getindexed(m, k)
  if i === :notfound
    m
  else
    kvs = []
    append!(kvs, m.kvs[1:i-1], m.kvs[i+2:end])
    PersistentArrayMap(kvs)
  end
end

function seq(m::PersistentArrayMap)
  # FIXME: We ought to return an iterable, not a realised vector.
  map(i -> MapEntry(m.kvs[i], m.kvs[i+1]), 1:2:length(m.kvs))
end

# These have limited size, so the simplicity of this method trumps efficiency
merge(x::PersistentArrayMap, y::PersistentArrayMap) = into(x, y)

function Base.:(==)(x::PersistentArrayMap, y::PersistentArrayMap)
  if x === y
    return true
  elseif count(x) !== count(y)
    return false
  else
    for i in 1:count(x)
      key = x.kvs[2*i-1]
      (v, j) = getindexed(y, key)
      if j === :notfound || v != x.kvs[2*i]
        return false
      end
    end
    return true
  end
end

##### Hash Maps

function getindexed(m::MapEntry, k, default, l)
  if m.key == k
    # The level at which an element was found (if found) tells you exactly what
    # it's effective hash is.
    m.value, l
  else
    default, :notfound
  end
end

function getindexed(m::EmptyMarker, _, default, _)
  default, :notfound
end

function getindexed(m::PersistentHashNode, k, default, l)
  next = m.ht[nth(hashseq(k), m.level) + 1]

  getindexed(next, k, default, m.level)
end

function getindexed(m::PersistentHashMap, k, default=nil)
  getindexed(m.root, k, default, 1)
end

function containsp(m::PersistentHashNode, e::MapEntry)
  (v, i) = getindexed(m, key(e), :notfound, m.level)
  i !== :notfound && v == val(e)
end

assoc(m::PersistentHashMap, k, v) = conj(m, MapEntry(k, v))

function addtomap(m::PersistentHashNode, e::MapEntry, _=0)
  h = nth(hashseq(key(e)), m.level) + 1
  next = m.ht[h]

  submap = addtomap(next, e, m.level)
  ht = copy(m.ht)
  ht[h] = submap

  PersistentHashNode(ht, m.level, sum(count, ht))
end

addtomap(x::MapEntry, y::PersistentHashNode, l) = addtomap(y, x, l)

addtomap(m::PersistentHashNode, e::EmptyMarker, _=0) = m
addtomap(e::EmptyMarker, m::PersistentHashNode, _=0) = m

addtomap(m::EmptyMarker, e::MapEntry, _=0) = e
addtomap(e::MapEntry, m::EmptyMarker, _=0) = e

addtomap(x::EmptyMarker, y::EmptyMarker, _=0) = x

function addtomap(e1::MapEntry, e2::MapEntry, l)
  if key(e1) == key(e2)
    e2
  else
    addtomap(addtomap(emptyhashnode(l+1), e1), e2)
  end
end

function conj(m::PersistentHashMap, e::MapEntry)
  (v, i) = getindexed(m, key(e))
  if i !== :notfound && val(e) == i
    m
  else
    PersistentHashMap(addtomap(m.root, e))
  end
end

function addtomap(x::PersistentHashNode, y::PersistentHashNode, l)
  ht = Base.Vector{MapNode}(undef, nodelength)

  for i in 1:nodelength
    ht[i] = addtomap(x.ht[i], y.ht[i], l)
  end

  PersistentHashNode(ht, l, sum(count, ht))
end

function merge(x::PersistentHashMap, y::PersistentHashMap)
  PersistentHashMap(addtomap(x.root, y.root, 1))
end

merge(x::PersistentArrayMap, y::PersistentHashMap ) = into(y, x)
merge(x::PersistentHashMap,  y::PersistentArrayMap) = into(x, y)

merge() = emptymap
# REVIEW: There's a more efficient way to merge N hashmaps in one downward
# pass. Currently I'm not seeing merge performance as any kind of bottleneck,
# but this is the kind of thing a more mature datastructures lib would think
# about.
merge(xs::Map...) = reduce(merge, xs)

function mergewith(f, m1, m2)
  if count(m1) <= count(m2)
    init = m2
    xs = m1
  else
    init = m1
    xs = m2
  end

  function rf(acc, e)
    if containsp(acc, key(e))
      update(acc, key(e), f, val(e))
    else
      conj(acc, e)
    end
  end

  reduce(rf, init, xs)
end

function dissoc(m::PersistentHashMap, k)
  # REVIEW: It's telling that I haven't actually hit this error in the months
  # I've been using this library. Is it just my style of programming?
  # Monotonicity has a lot of benefits. And there's always `selectkeys`.
  throw("not implemented")
end

gather(acc, m::EmptyMarker) = acc
gather(acc, m::MapEntry) = conj(acc, m)
gather(acc, m::PersistentHashNode) = reduce(gather, acc, m.ht)

function seq(m::PersistentHashMap)
  gather(emptyvector, m.root)
end

function selectkey(m::Map, k)
  emptymarker = gensym()
  v = get(m, k, emptymarker)
  if v === emptymarker
    nil
  else
    MapEntry(k, v)
  end
end

# TODO: Override `into` for EmptyMap as we did for vectors.
function selectkeys(m::Map, ks)
  into(emptymap, map(x -> selectkey(m, x)) ∘ remove(x -> x === nil), ks)
end

function Base.:(==)(x::PersistentHashMap, y::PersistentHashMap)
  x.root == y.root
end

function Base.:(==)(x::PersistentHashNode, y::PersistentHashNode)
  if count(x) !== count(y)
    return false
  else
    every(==, x.ht, y.ht)
  end
end

function Base.:(==)(x::PersistentArrayMap, y::PersistentHashMap)
  y == x
end

function Base.:(==)(x::PersistentHashMap, y::PersistentArrayMap)
  if count(x) !== count(y)
    return false
  else
    every(k -> get(x, k) == get(y, k), keys(y))
  end
end

iterate(m::EmptyMap) = nothing

function iterate(m::PersistentArrayMap)
  first(m), 2
end

function iterate(m::PersistentArrayMap, k)
  if k > count(m)
    nothing
  else
    MapEntry(m.kvs[2*k-1], m.kvs[2*k]), k+1
  end
end

function iterate(m::PersistentHashMap)
  first(m), rest(seq(m))
end

# FIXME: This is very inefficient. Store a cursor or something. Better yet let
# the head get collected, but that won't help in this case...
function iterate(m::PersistentHashMap, state)
  if emptyp(state)
    nothine
  else
    first(state), rest(state)
  end
end
