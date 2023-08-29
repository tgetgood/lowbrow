abstract type Sequential end

function reduce(f, coll)
  reduce(f, f(), coll)
end

# General reduce for anything sequential
function reduce(f, init, coll)
  if emptyp(coll)
    init
  else
    reduce(f, f(init, first(coll)), rest(coll))
  end
end

function transduce(xform, f, to, from)
  g = xform(f)
  # Don't forget to flush state after input terminates
  g(reduce(g, to, from))
end

function transduce(xform, f, from)
  g = xform(f)
  g(reduce(g, g(), from))
end

function into()
  emptyvector
end

function into(x)
  x
end

function into(to, from)
  reduce(conj, to, from)
end

function into(to, xform, from)
  transduce(xform, conj, to, from)
end

function drop(n, coll)
  if n == 0
    coll
  else
    drop(n - 1, rest(coll))
  end
end

function take(n, coll)
  out = emptyvector
  s = coll
  for i in 1:n
    f = first(s)
    if f === nothing
      break
    else
      out = conj(out, f)
      s = rest(s)
    end
  end
  return out
end

function conj()
  emptyvector
end

function conj(x)
  x
end

function concat(xs, ys)
  into(xs, ys)
end

function every(p, xs)
  reduce((x, y) -> x && y, true, map(p, xs))
end

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

function mapindex(f::Function)
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

function mapindex(f::Function, xs::Union{Base.Vector, Sequential})
  into(empty(xs), mapindex(f), xs)
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

function partition(n)
  acc = emptyvector
  function (emit)
    function inner()
      emit()
    end
    function inner(result)
      if count(acc) > 0
        emit(result, acc)
      else
        emit(result)
      end
    end
    function inner(result, next)
      acc = conj(acc, next)
      if count(acc) == n
        t = acc
        acc = emptyvector
        emit(result, t)
      else
        emit(result)
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

# NTuple compatibility

function rest(xs::NTuple)
  xs[2:end]
end

function count(xs::NTuple)
  length(xs)
end
