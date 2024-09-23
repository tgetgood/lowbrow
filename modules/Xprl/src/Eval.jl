module Eval

import DataStructures as ds

import ..Forms
import ..System

struct μ
  receiver
  params
  immediates
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

function apply(cont, env, f::μ, arg)

end

function apply(cont, env, f::Function, arg)
  # REVIEW: Should I splat on primitives? *Most* of them will take a list of
  # args, but will it really be all?
  f(arg...)
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

  if v == ds.nil
    @error "asserts are failing silent for some reason."
    throw("Error evaluating undefined symbol.")
  end
  cont(ds.get(env, f))
end

function evalimmediate(cont, context, form::Forms.ImmediatePair)
  head = form.head

end

struct NestedContext
  params
  env
end

function createμ(cont, env, argsym, body)
  context = NestedContext(syms, env)
  mubody = evalimmediate(context, body)
end

end # module
