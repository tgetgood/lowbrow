import Base

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
