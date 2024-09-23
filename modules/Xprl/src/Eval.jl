module Eval

import DataStructures as ds

import ..Forms
import ..System
import ..Receivers as rec

struct Applicative
  f::Function
end

struct μ
  env
  argsym
  body
end

function uniquep(v)
  s = ds.emptyset
  for e in v
    if ds.containsp(s, e)
      return false
    end
    s = ds.conj(s, e)
  end
  return true
end

# REVIEW: I'm assuming applicatives always receive a list of arguments. That may
# or may not hold on further review.
function apply(cont, env, f::Applicative, args)
  collector = rec.collector(length(args), xs -> cont(f.f(xs...)))

  # TODO: Use the system scheduler so that these can be stolen if needed.
  ds.mapindexed((i, x) -> eval(y -> rec.receive(collector, rec.CubbyWrite(i, y)),
                               env,
                               x),
                args)
  nothing
end

function apply(cont, env, f::μ, arg)

end

function apply(cont, env, f::Function, arg)
  # REVIEW: Should I splat on primitives? *Most* of them will take a list of
  # args, but will it really be all?
  f(cont, env, arg)
end

function eval(cont, env, f::Forms.Pair)
  function next(x)
    apply(cont, env, x, f.tail)
  end
  eval(next, env, f.head)
end

function eval(cont, env, f::Forms.Symbol)
  # REVIEW: This assertion will be costly. But then we're caching, so probably
  # worth it.
  v = ds.containsp(env, f)

  if v === false
    throw("Error undefined symbol: " * string(f))
  end
  cont(ds.get(env, f))
end

# value types
eval(cont, env, x) = cont(x)

function evalimmediate(cont, env, form::Forms.Immediate)
  evalimmediate(cont, env, form.content)
end

function evalimmediate(cont, env, form)
  cont(form)
end

function createμ(cont, env, args)
  argsym = args.head
  body = args.tail.head

  function next(argsym, evbody)
    cont(μ(env, argsym, evbody))
  end

  eval(next, env, body)
end

end # module
