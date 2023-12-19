module DataStructures

import Base: string, hash, ==, length, iterate, put!, bind, reverse, get, merge, keys, values, first, map, filter, getindex, eltype, show, last, empty, repeat, split, take!, put!, close, lock, unlock, isready

# N.B.: Base.rest is broken for ranges and zip iterators. It returns the
# collection itself. Don't import it.

# How many bits of hash are used at each level of the HAMT?
hashbits = 5
nodelength = 2^hashbits
nil = nothing

include("./util.jl")

include("./sexps.jl")
include("./sequential.jl")
include("./vector.jl")
include("./transientvector.jl")
include("./list.jl")
include("./map.jl")
include("./set.jl")
include("./queue.jl")
include("./async.jl")
include("./juliatypes.jl")

# Sequential
export first, rest, take, drop, reduce, transduce, into, map, filter, interpose, dup, cat, partition, seq, seqcompose, zip, split, interleave, inject, takewhile, dropwhile

# Vectors
export emptyvector, nth, vec, vector

# Lists

export list, tolist

# Maps
export emptymap, assoc, update, dissoc, containsp, hashmap, vals, associn, updatein, getin, mapkeys, mapvals

# Sets
export emptyset, disj, set

# Queues
export Queue, queue, emptyqueue, closedp, emptystream, put!, Stream, stream

# Generic
export conj, count, empty, emptyp, nil, keyword, name, symbol, withmeta, meta, every

# Types
export Keyword, Map, Vector, MapEntry, List

# Transients
export transient!, persist!, conj!

# Async
export Atom, deref, swap!, pub, subscribe, tap

# other
export handleerror

# Mutable Julia collections
export into!

## Julia conventions vs my tendency to use clojure names...
values(m::Map) = vals(m)

# REVIEW: julia Base fns that are essentially similar, like `get`, `keys`,
# `reverse`, &c. I've overloaded in Base. Fns that share names but do something
# utterly different (`conj`) I've left only in this module.
#
# I don't know if that's a reasonable thing to do. being able to call
# Base.reverse on a sequence from this module makes perfect sense, as does
# extending Base Dict methods to Maps, but it creates a confusing grey zone that
# I don't think I like.

end
