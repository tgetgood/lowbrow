# FIXME: This is incorrect and incomplete. Not that it could pass for complete
# even at a glance...

abstract type Set <: Sequential end

const arraysetthreashold = 8

struct PersistentArraySet
  elements:Vector
end

emptyset = PersistentArraySet([])

first(s::Set) = first(seq(s))
rest(s::Set) = rest(seq(s))

seq(s::PersistentArraySet) = s.elements

count(s::PersistentArraySet) = count(s.elements)

function containsp(s::PersistenArraySet, x)
  for e in s.elements
    if e == x
      return true
    end
  end
  return false
end

struct PersistentHashSet
  ht::Vector
  count::Unsigned
end

count(s::PersistenHashSet) = s.count


function conj(s::Set, x)
  for e in s.elements
    if e == x
      return s
    end
  end
  if count(s.elements) >= arraysetthreashold
    conj(into(emptyhashset, s.elements), x)
  else
    PersistentArraySet(conj(s.elements, x))
  end
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
end
