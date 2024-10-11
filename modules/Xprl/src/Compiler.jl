module Compiler

import DataStructures as ds

import ..System
import ..Receivers as rec
import ..AST as ast
import ..Environment as E

# FIXME: This can be expensive to compute. We need a flag of some sort so as not
# to do it more than once for a given value.
valuep(x::Int) = true
valuep(x::String) = true
valuep(x::Bool) = true
valuep(x::ds.Vector) = ds.every(valuep, x)
valuep(x::ds.Map) = ds.every(e -> valuep(ds.key(e)) && valuep(ds.val(e)), x)
valuep(x) = false

function invoke(env, x)
  if valuep(x)
    x
  else
   ast.Immediate(env, compile(x))
  end
end

function invoke(env, x::ast.Immediate)
  y = invoke(env, x.form)
  n = ast.Immediate(env, y)
  if x == y
    n
  else
    compile(n)
  end
end

function invoke(env, x::ds.Symbol)
  v = E.get(env, x, :notfound)
  if v !== :notfound
    ast.mergelocals(env, compile(v))
  elseif E.unboundp(env, x)
    ast.Immediate(env, x)
  else
    @info string(env)
    throw("Unresolved symbol: " * string(x))
  end
end

function invoke(env, l::ast.ArgList)
  ast.arglist(map(x -> compile(ast.Immediate(env, x)), l.args))
end

function invoke(env, x::ast.Pair)
  compile(ast.Application(env, ast.Immediate(env, x.head), x.tail))
end

function apply(env, f::ast.PrimitiveFunction, args)
  cargs = compile(args)
  if ast.reduced(cargs)
    f.f(cargs...)
  else
    ast.Application(env, f, cargs)
  end
end

function apply(env, f::ast.PrimitiveMacro, args)
  f.f(env, args...)
end

function apply(env, f::ast.Mu, arg)
  compile(ast.mergelocals(env, ast.bind(f.body, f.arg, arg)))
end

function apply(env, f, arg)
  ast.Application(env, f, arg)
end

function compile(form)
  form
end

function compile(f::ast.Mu)
  ast.Mu(f.env, f.arg, compile(f.body))
end

function compile(f::ast.PartialMu)
  ast.PartialMu(f.env, compile(f.arg), compile(f.body))
end

function compile(form::ast.ArgList)
  ast.arglist(map(x -> compile(x), form.args))
end

function compile(form::ast.Immediate)
  invoke(form.env, form.form)
end

function compile(env, form::ast.Pair)
  ast.Pair(compile(env, form.head), compile(env, form.tail))
end

function compile(form::ast.Application)
  apply(form.env, compile(form.head), form.tail)
end

function compile(form::ast.TopLevel)
  form.compiled
end

"""
Takes a form as pure syntax, replaces the meaning of all symbols (the lexical
environment) with the one provided, and compiles the result.
"""
function compilein(env, form)
  rform = ast.reground(env, form)
  cform = compile(ast.Immediate(env, rform))
end

end # module
