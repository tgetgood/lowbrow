module CPSCompiler

import DataStructures as ds

import ..AST as ast
import ..Environment as E

struct Ch
  ret
  chs
end

chans(c) = Ch(c, ds.emptymap)

function eval(c, env, form::ds.Symbol)
  if E.unboundp(env, form)
    c.ret("???")
  end

  v = E.get(env, form, :notfound)
  if v === :notfound
    throw("Symbol not defined: " * string(form))
  else
    c.ret(v)
  end
end

function eval(c, env, form::ast.Pair)
  compile(
    c,
    env,
    ast.Application(env, ast.immediate(env, form.head), form.tail)
  )
end

function eval(c, env, form::ast.Immediate)
  next = chans(f -> eval(c, env, f))
  eval(next, env, form.form)
end

function eval(c, env, x)
  c.ret(x)
end

function apply(c, env, f::ast.PrimitiveMacro, tail)
  next = chans(xs -> f.f(c, env, xs...))
  compile(next, env, tail)
end

function apply(c, env, f::ast.PrimitiveFunction, tail)
  next = chans(xs -> c.ret(f.f(xs...)))
  compile(next, env, tail)
end

function compile(c, env, form)
  c.ret(form)
end

function compile(c, env, form::ast.Application)
  next = chans(h -> apply(c, env, h, form.tail))
  compile(next, env, form.head)
end

function compile(c, env, form::ast.Immediate)
  eval(c, env, form.form)
end

function entry(ret, env, form)
  compile(Ch(ret, ds.emptymap), env, ast.immediate(env, form))
end

end # module
