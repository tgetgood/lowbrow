module Eval

import DataStructures as ds

import ..System
import ..Receivers as rec

struct Applicative
  f::Function
end

struct μ
  form
  env
  argsym
  body
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

  nothing
end

function apply(cont, env, f::Function, args)
  f(cont, env, args)
  nothing
end

function eval(cont, env, f::ds.Pair)
  function next(x)
    apply(cont, env, x, f.tail)
  end
  eval(next, env, f.head)
  nothing
end

function eval(cont, env, f::ds.Symbol)
  # REVIEW: This assertion will be costly. But then we're caching, so probably
  # worth it.
  v = ds.containsp(env, f)

  if v === false
    throw("Error undefined symbol: " * string(f))
  end
  cont(ds.get(env, f))
  nothing
end

# value types
function eval(cont, env, x)
  cont(x)
  nothing
end

function evalimmediate(cont, env, form::ds.Immediate)
  evalimmediate(cont, env, form.content)
end

function evalimmediate(cont, env, form)
  cont(form)
end

function createμ(cont, env, args)
  argsym = args[1]
  body = args[2]

  form = ds.Pair(ds.Symbol(["μ"]), ds.vector(argsym, body))

  function next(evbody)
    cont(μ(form, env, argsym, evbody))
  end

  eval(next, env, body)
  nothing
end

end # module
