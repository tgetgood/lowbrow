abstract type Set <: Sequential end

# FIXME: Basically don't use hashsets because they're not implemented. This will
# scale *very* poorly.
const arraysetthreashold = typemax(Int)

struct EmptySet <: Set end

emptyset = EmptySet()

empty(s::Set) = emptyset
count(s::EmptySet) = 0

emptyp(s::EmptySet) = true
emptyp(s::Set) = false

seq(s::EmptySet) = emptyvector

function conj(s::EmptySet, x)
  PersistentArraySet([x])
end

struct PersistentArraySet{T} <: Set
  elements::Base.Vector{T}
end

first(s::Set) = first(seq(s))
rest(s::Set) = rest(seq(s))

## N.B.: `seq` on sets is necessary to facilitate iteration, but sets are
## unordered, and there's no guarantee that the same set will yield the same
## sequence twice.
seq(s::PersistentArraySet) = s.elements

count(s::PersistentArraySet) = length(s.elements)

containsp(s::Set, x) = getindexed(s, x) !== :notfound

set(xs...) = into(emptyset, xs)

# FIXME: Check for repeats!!
function arrayset(elements)
  if length(elements) === 0
    emptyset
  else
    PersistentArraySet(unique(elements))
  end
end

function getindexed(s::PersistentArraySet{T}, x::S) where {T, S}
  :notfound
end

function getindexed(s::PersistentArraySet{T}, x::T) where T
  for i in 1:count(s)
    if x == s.elements[i]
      return i
    end
  end
  return :notfound
end

function conj(s::PersistentArraySet, x)
  if containsp(s, x)
    s
  else
    if count(s) == arraysetthreashold
      conj(into(emptyhashset, s), x)
    else
      arrayset(push!(copy(s.elements), x))
    end
  end
end

function disj(s::PersistentArraySet, x)
  i = getindexed(s, x)
  if i === :notfound
    s
  else
    arrayset(append!(s.elements[begin:i-1], s.elements[i+1:end]))
  end
end

## FIXME: Not finished.
##### Hash Sets

struct HashSetNode
  ht::Base.Vector
  count::Int
  level::Int
end

# REVIEW: specialise on isbits types and use the actual bits as the hash? That
# would simplify a lot of things, and save a good amount of space for types with
# less than 64 bits.
#
# Not a priority by any means, but an intriguing puzzle.
struct PersistentHashSet
  root::HashSetNode
end

count(s::PersistentHashSet) = s.root.count

getindexed(s::PersistentHashSet, x) = getindexed(s.root, x, 1)

getindexed(s::EmptyMarker, x, _) = :notfound

# REVIEW: I'm not using a special "entry" type to denote a hit. Rather anything
# which is not a recusive node or an empty marker is a value. There's an edge
# there that I think is harmless, but let's see if it cuts me.
getindexed(s, x, l) = l

function getindexed(s::PersistentHashNode, x, _)
  i = nth(hashseq(x), s.level) + 1

  getindexed(s.ht[i], x, s.level + 1)
end

function addtoset(s::EmptyMarker, x, _)

end

function conj(s::PersistentHashSet, x)
  if getindexed(s, x) === :notfound
    PersistentHashSet(addtoset(s.root, x))
  else
    s
  end
end

function disj(s::PersistentHashSet, x)
  throw("not implemented")
end

# Allow nodes to have between nodelength and nodelength/2 elements.
# Each node stores highest and lowest stored value.
# Insert into tree recursively. If a node grows too large, split it and
# propagate the changes to the parent.
#
# So long as we can ensure that no node will ever have less than nodelength/2
# elements (except the rightmost), then we know the tree is balanced and lookup
# and insertion are O(logn).
#
# Caveat: Identity is derived from the comparison function. This might not
# always be what you want.
struct PersistentSortedSet
  root
  by::Function
  lt::Function
end

function string(s::Set)
  "#{" * transduce(map(string) ∘ interpose(", "), *, "", seq(s)) * "}"
end
