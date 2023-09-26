abstract type Map <: Sequential end

abstract type MapNode end

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

struct EmptyMap <: Map
end

const emptymap = EmptyMap()

# Clojure uses 8 and I don't want to dig into it just yet.
# TODO: Analysis
const arraymapsizethreashold = 8

struct PersistentArrayMap <: Map
  kvs::Tuple
end

struct EmptyMarker <: MapNode
end

const emptymarker = EmptyMarker()

# N.B.: It's important that nodes not be maps themselves since nodes with
# different levels cannot be merged sensibly and so passing subnodes around as
# full fledged maps is bound to end in confusion and disaster.
struct PersistentHashNode <: MapNode
  ht::NTuple{Int(nodelength), MapNode}
  level::UInt
  count::UInt
end

const emptyhash = NTuple{Int(nodelength), MapNode}(
  map(x -> emptymarker, 1:nodelength)
)

emptyhashnode(level) = PersistentHashNode(emptyhash, level, 0)

# REVIEW: One extra memory indirection makes all the ensuing code cleaner. I'll
# consider it worth it until proven otherwise.
struct PersistentHashMap <: Map
  root::PersistentHashNode
  # ht::NTuple{Int(nodelength), MapNode}
  # count::UInt
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

empty(m::Map) = emptymap

count(m::EmptyMarker) = 0
count(m::PersistentHashNode) = m.count
count(m::MapEntry) = 1
count(m::EmptyMap) = 0
count(m::PersistentArrayMap) = length(m.kvs) >> 1 # inline kvs
count(m::PersistentHashMap) = m.root.count

emptyp(m::Map) = count(m) == 0

conj(m::Map, x::Nothing) = m
conj(m::Map, e::MapEntry) = assoc(m, e.key, e.value)
conj(m::Map, v::Vector) = assoc(m, v[1], v[2])

seq(x::Nothing) = emptyvector

# Defer to `seq` for concrete type unless overridden.
first(m::Map) = first(seq(m))
rest(m::Map) = rest(seq(m))

get(m::Nothing, k) = nil
get(m::Nothing, k, default) = default
get(m::EmptyMap, x) = get(m, x, nothing)
get(m::EmptyMap, x, default) = default

function getindexed(m::EmptyMap, k)
  nothing, :notfound
end

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

get(m::Map, k, default=nil) = getindexed(m, k, default)[1]

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

function associn(m::Map, ks::Vector, v)
  if count(ks) == 1
    assoc(m, first(ks), v)
  else
    k = first(ks)
    assoc(m, k, associn(get(m, k, emptymap), rest(ks), v))
  end
end

function associn(m::Map, ks, v)
  associn(m, vec(ks), v)
end

function assoc(m::Map, k, v, kvs...)
  @assert length(kvs) % 2 == 0

  into(assoc(m, k, v), partition(2), kvs)
end

assoc(m::Map, k::Nothing, v) = throw("nothing is not a valid map key.")
assoc(x::Nothing, k, v) = PersistentArrayMap((k, v))
assoc(m::EmptyMap, k, v) = PersistentArrayMap((k, v))

function assoc(m::PersistentArrayMap, k, v)
  if count(m) >= arraymapsizethreashold
    assoc(into(emptyhashmap, m), k, v)
  else
    (_, i) = getindexed(m, k)

    if i === :notfound
      PersistentArrayMap((m.kvs...,k,v))
    else
      PersistentArrayMap((
        m.kvs[1:i-1]...,
        m.kvs[i+2:end]...,
        k,v
      ))
    end
  end
end

function dissoc(m::PersistentArrayMap, k)
  (_, i) = getindexed(m, k)
  if i === :notfound
    m
  else
    PersistentArrayMap((m.kvs[1:i-1]..., m.kvs[i+2:end]...))
  end
end

function seq(m::PersistentArrayMap)
  map(i -> MapEntry(m.kvs[i], m.kvs[i+1]), 1:2:length(m.kvs))
end


# REVIEW: Profile and see if first often comes without rest. This isn't useful
# unless that's the case.
function first(m::PersistentArrayMap)
  MapEntry(m.kvs[1], m.kvs[2])
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

function getindexed(m::PersistentHashNode, k, default, l)
  next = m.ht[nth(hashseq(k), m.level) + 1]

  if next === emptymarker
    default, :notfound
  else
    getindexed(next, k, default, m.level)
  end
end

function getindexed(m::PersistentHashMap, k, default=nil)
  getindexed(m.root, k, default, 1)
end

function assoc(m::PersistentHashNode, k, v, level=nil)
  h = nth(hashseq(k), m.level) + 1
  next = m.ht[h]

  if next === emptymarker
    # New entry increases size by one.
    PersistentHashNode(assoc(m.ht, h, MapEntry(k, v)), m.level, m.count + 1)
  else
    submap = assoc(next, k, v, m.level)
    ht = assoc(m.ht, h, submap)
    c = sum(map(count, ht); init=0)

    PersistentHashNode(ht, m.level, c)
  end
end

function assoc(e::MapEntry, k, v, l=0)
  if e.key == k
    e
  else
    assoc(assoc(emptyhashnode(l+1), e.key, e.value), k, v)
  end
end

function assoc(
  t::NTuple{Int(nodelength),MapNode}, i, v
)::NTuple{Int(nodelength),MapNode}
  tuple(t[1:i-1]..., v, t[i+1:end]...)
end

function assoc(m::PersistentHashMap, k, v)
  (val, i) = getindexed(m, k)
  if i !== :notfound && val == v
    m
  else
    PersistentHashMap(assoc(m.root, k, v))
  end
end

function dissoc(m::PersistentHashMap, k)
  throw("not implemented")
end

gather(acc, m::EmptyMarker) = acc
gather(acc, m::MapEntry) = conj(acc, m)
gather(acc, m::PersistentHashNode) = reduce(gather, acc, m.ht)

function seq(m::PersistentHashMap)
  gather(emptyvector, m.root)
end

function update(m::Map, k, f, v...)
  assoc(m, k, f(get(m, k), v...))
end

function updatein(m::Map, ks, f, v...)
  associn(m, ks, f(getin(m, ks), v...))
end

function hashmap(args...)
  @assert length(args) % 2 == 0
  into(emptymap, partition(2), args)
end

merge(x::Map) = x

# TODO: Merge can be implemented much more efficiently.
function merge(x::Map, y::Map)
  into(x, y)
end

function string(x::MapEntry)
  string(x.key) * " " * string(x.value)
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

function keys(m::Map)
  map(x -> x.key, seq(m))
end

function vals(m::Map)
  map(x -> x.value, seq(m))
end

##### Ordered Maps
##
## associative datastructure that preserves insertion order on iteration.
## Specifically, this means that `keys` and `vals` return the keys and vals of
## the map in the order in which they were inserted.

## N.B.: performance will not be stellar if you overwrite keys frequently in a
## large map. Getting the list of keys or vals *should* always be O(n) --- O(1)
## per iteration step --- but the constants grow as keeping track of order gets
## more involved.

## The above isn't true because I haven't implemented lazy evaluation
## yet... In reality, updating a key is O(n) worst case, but getting the keys is
## O(1).

struct OrderedMap <: Map
  inner::Map
  keyseq::Vector
end

const emptyorderedmap = OrderedMap(emptymap, emptyvector)

function assoc(m::OrderedMap, k, v)
  m2 = assoc(m.inner, k, v)
  if containsp(m, k)
    keyseq = conj(filter(x -> x != k, m.keyseq), k)
  else
    keyseq = conj(m.keyseq, k)
  end
  return OrderedMap(m2, keyseq)
end

function dissoc(m::OrderedMap, k)
  OrderedMap(
    dissoc(m.inner, k),
    filter(x -> x != k, m.keyseq)
  )
end

get(m::OrderedMap, k, default) = get(m.inner, k, default)

seq(m::OrderedMap) = map(k -> MapEntry(k, get(m, k)), m.keyseq)

keys(m::OrderedMap) = m.keyseq

vals(m::OrderedMap) = map(k -> get(m, k), m.keyseq)

count(m::OrderedMap) = count(m.keyseq)

function zipmap(x, y)
  i = min(count(x), count(y))
  reduce((a, i) -> assoc(a, x[i], y[i]), emptymap, 1:i)
end
