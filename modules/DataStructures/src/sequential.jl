abstract type Sequential end

""" Returns `true` iff the collection `x` contains no elements. """
emptyp(x::Sequential) = count(x) == 0
emptyp(x) = length(x) == 0

struct Reduced{T}
  value::T
end

# REVIEW: This is too much like Scala's null zoo for my liking.
struct NoEmission end
const none = NoEmission()

function reduced(x)
  throw(Reduced(x))
end

function reduce(f, coll)
  reduce(f, f(), coll)
end

function reduce(f, init, coll...)
  try
    ireduce(f, init, coll...)
  catch r
    if r isa Reduced
      if r.value === nothing
        none
      else
        r.value
      end
    else
      throw(r)
    end
  end
end

# Fallback reduce impl for anything sequential
function ireduce(f, init, coll)
  if emptyp(coll)
    init
  else
    reduce(f, f(init, first(coll)), rest(coll))
  end
end

##### TODO: split/join funcitons for the from/to collections to allow parallel
##### transduction. This will require knowing which transducers can be run in
##### parallel.
function transduce(xform, f, to, from)
  g = xform(f)
  # Don't forget to flush state after input terminates
  g(reduce(g, to, from))
end

function transduce(xform, f, from)
  g = xform(f)
  g(reduce(g, g(), from))
end

function ireduce(f, acc, lists...)
  if every(!emptyp, lists)
    reduce(f, f(acc, map(first, lists)...), map(rest, lists)...)
  else
    acc
  end
end

function transduce(xform, f, to, from...)
  g = xform(f)
  g(reduce(g, to, from...))
end

## Fallback `into` implementations.
##
## Collection specific specialisations are recommended.
into() = emptyvector
into(x) = x
into(to, from) = reduce(conj, to, from)
into(to, xform, from) = transduce(xform, conj, to, from)

function drop(n)
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      if n === 0
        emit(result, next)
      else
        n -= 1
        result
      end
    end
    return inner
  end
end

drop(n, coll) = into(empty(coll), drop(n), coll)

function take(n)
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      if n === 1
        reduced(emit(result, next))
      else
        n -= 1
        emit(result, next)
      end
    end
    return inner
  end
end

take(n, coll) = into(empty(coll), take(n), coll)

# function seqcompose(xforms)
#   function (emit)
#     function inner(xs...)
#       try
#         first(xforms)(xs...)
#       catch r
#         if r isa Reduced
#           xforms = rest(xforms)
#           if emptyp(xforms)
#             throw r
#           else
#             emit(unreduce(r))

conj() = emptyvector
conj(x) = x

concat(xs, ys) = into(xs, ys)

# This is an odd one. The "natural" implementation for `every` throws away the
# accumulator arg since only the last one matters. But that can't be composed
# with other transducers.
#
# As is, this can be composed, but will short circuit and throw away the
# downstream computation the first time `p` evaluates to `false`. I think that's
# the correct behaviour, but it's still weird...
function every(p)
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      if p(next)
        emit(result, next)
      else
        reduced(none)
      end
    end
    return inner
  end
end

lastarg(xs...) = xs[end]
every(p, xs) = transduce(every(p), lastarg, nil, xs) !== none

function cat()
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      reduce(emit, result, next)
    end
    function inner(result, next::Base.Vector)
      Base.reduce(emit, next, init=result)
    end
    return inner
  end
end

function map(f::Function)
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      emit(result, f(next))
    end
    inner
  end
end

function map(f, xs::Sequential)
  into(empty(xs), map(f), xs)
end

function mapindexed(f::Function)
  index = 0
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      index += 1
      emit(result, f(next, index))
    end
    inner
  end
end

function mapindexed(f::Function, xs::Union{Base.Vector, Sequential})
  into(empty(xs), mapindexed(f), xs)
end

function filter(p::Function)
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, next)
      if p(next) == true
        emit(result, next)
      else
        result
      end
    end
    inner
  end
end

function filter(p, xs::Sequential)
  into(empty(xs), filter(p), xs)
end

function interpose(delim)
  function (emit)
    started = false
    function inner()
      emit()
    end
    function inner(res)
      emit(res)
    end
    function inner(res, next)
      if started
        return emit(emit(res, delim), next)
      else
        started = true
        return emit(res, next)
      end
    end
    return inner
  end
end

function aftereach(delim)
  function (emit)
    function inner()
      emit()
    end
    function inner(res)
      emit(res)
    end
    function inner(res, next)
      emit(emit(res, next), delim)
    end
    return inner
  end
end

# FIXME: What's going on here?

# Interleave is a higher order form of transducer (as is map in general). The
# current implementation only works for a single argument at each step, which is
# wrong, but whenever I try to generalise I quickly wind up with a mess.

# function interleave()
#   i = 1
#   function inner(emit)
#   end
# end

function partition(n)
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
      if count(acc) == n
        t = vec(acc)
        acc = []
        emit(result, t)
      else
        result
      end
    end
    return inner
  end
end

function partition(n, xs)
  into(empty(xs), partition(n), xs)
end

function dup(emit)
  function inner()
    emit()
  end
  function inner(acc)
    emit(acc)
  end
  function inner(acc, next)
    emit(emit(acc, next), next)
  end
  return inner
end

function prepend(head)
  function (emit)
    function inner()
      reduce(emit, emit(), head)
    end
    function inner(res)
      emit(res)
    end
    function inner(res, next)
      emit(res, next)
    end
  end
end

function zip()
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, xs...)
      emit(result, vec(xs))
    end
  end
end

zip(colls...) = transduce(zip(), conj, emptyvector, colls...)
