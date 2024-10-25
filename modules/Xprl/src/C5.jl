module C5

import Base: get, string, show

import DataStructures as ds
import DataStructures: walk
import ..System as sys
import ..AST as ast
import ..AST: inspect, reduced

##### Context of Interpretation

struct Context
  bindings::ds.Map
  stack::ds.Vector
end

string(x::Context) = string(x.form)

function show(io::IO, mime::MIME"text/plain", s::Context)
  print(io, string(s))
end

context(m::ds.Map) = Context(ds.emptymap, ds.emptyvector)

"""
Embeds a form recursively in a fixed lexical environment.
"""
function declare(m::Context, k)
  Context(ds.dissoc(m.bindings, k), ds.conj(m.stack, k))
end

containsp(m::Context, k) = ds.containsp(m.bindings, k)

function unboundp(m::Context, k)
  for j = m.stack
    if j == k
      return true
    end
  end
  return false
end

function extend(m::Context, k, v)
  # @assert m.stack[1] == k "Cannot apply to inner μs before outer μs."

  Context(ds.assoc(m.bindings, k, v), ds.into(ds.emptyvector, m.stack))
end

##### Eval

function eval(c, env, f::ast.Symbol)
  if ds.containsp(env.bindings, f.name)
    @info "dyn", string(f.name), string(env.bindings), string(env.stack)
    compile(c, env, get(env.bindings, f.name))
  elseif unboundp(env, f.name)
    @info "unbound"
    sys.succeed(c, ast.Immediate(f))
  else
    v = get(f.env, f.name, :notfound)
    if v === :notfound
      throw("Unresolvable symbol: " * string(f.name))
    else
      @info "lex", string(f.name), string(v)
      @info "with", string(ds.keys(env.bindings)), string(env.stack)
      compile(c, env, v)
    end
  end
end

function eval(c, env, f::ast.Immediate)
  function next(x::ast.Immediate)
    sys.succeed(c, ast.Immediate(x))
  end
  function next(x)
    eval(c, env, x)
  end
  compile(sys.withcc(c, :return, next), env, f)
end

function eval(c, env, f::ast.Application)
  next(x::ast.Application) = sys.succeed(c, ast.Immediate(x))
  next(x) = eval(c, env, x)
  compile(sys.withcc(c, :return, next), env, f)
end

function eval(c, env, f::ds.Vector)
  function next(v)
    sys.succeed(c, v)
  end

  coll = sys.collector(sys.withcc(c, :return, next), ds.count(f))

  function runner((i, f))
    function next(x)
      sys.receive(coll, i, x)
    end
    eval(sys.withcc(c, :return, next), env, f)
  end

  tasks = ds.into(
    ds.emptyvector,
    ds.interleave(),
    ds.repeat(:run),
    ds.mapindexed(tuple, f)
  )
  sys.emit(sys.withcc(c, :run, runner), tasks...)
end

function eval(c, env, f::ast.Pair)
  compile(c, env, ast.Application(
    ast.immediate(f.head),
    f.tail
  ))
end

function eval(c, env, f)
  sys.succeed(c, f)
end

##### Apply

function apply(c, env, f::ast.Application, t)
  function next(a::ast.Application)
    sys.succeed(c, ast.Application(f, t))
  end
  function next(a)
    apply(c, env, a, t)
  end
  apply(sys.withcc(c, :return, next), env, f.head, f.tail)
end

function apply(c, env, f::ast.Mu, t)
  e = extend(env, f.arg, t)
  compile(c, e, f.body)
end

function apply(c, env, f::ast.PartialMu, t)
  sys.succeed(c, ast.Application(f, t))
end

function apply(c, env, f::ast.PrimitiveMacro, t)
  f.f(c, env, t)
end

function apply(c, env, f::ast.PrimitiveFunction, t)
  function next(t)
    @info string(t)
    if ast.reduced(t)
      sys.succeed(c, f.f(t...))
    else
      sys.succeed(c, ast.Application(f, t))
    end
  end

  inspect(t)
  compile(sys.withcc(c, :return, next), env, t)
end

function apply(c, env, f::ast.Immediate, t)
  sys.succeed(c, ast.Application(f, t))
end

function apply(c, env, f, t)
  @info "failed application: " * string(typeof(f))
  sys.succeed(c, ast.Application(f, t))
end

##### Compile

function compile(c, env, f::ds.Vector)
  function next(v)
    sys.succeed(c, v)
  end

  coll = sys.collector(sys.withcc(c, :return, next), ds.count(f))

  function runner((i, f))
    function next(x)
      sys.receive(coll, i, x)
    end
    compile(sys.withcc(c, :return, next), env, f)
  end

  tasks = ds.into(
    ds.emptyvector,
    ds.interleave(),
    ds.repeat(:run),
    ds.mapindexed(tuple, f)
  )
  sys.emit(sys.withcc(c, :run, runner), tasks...)
end

function compile(c, env, f::ast.Symbol)
  sys.succeed(c, f)
end

function compile(c, env, f::ast.Immediate)
  eval(c, env, f.form)
end

function compile(c, env, f::ast.Application)
  next(head) = apply(c, env, head, f.tail)
  compile(sys.withcc(c, :return, next), env, f.head)
end

function compile(c, env, f::ast.TopLevel)
  compile(c, env, f.form)
end

function compile(c, env, f::ast.Mu)
  next(x) = sys.succeed(c, ast.Mu(f.arg, x))
  e = declare(env, f.arg)
  compile(sys.withcc(c, :return, next), e, f.body)
end

function compile(c, env, f::ast.PartialMu)
  sys.succeed(c, f)
end

function compile(c, env, f::ast.BuiltIn)
  sys.succeed(c, f)
end

function compile(c, env, f)
  @warn "compile fallthrough: " * string(typeof(f))
  sys.succeed(c, f)
end

##### Top level entry point

"""
Interprets `form` in the lexical environment `env` as if the form were read from
that environment. `c` is the bundle of channels to which messages may be emitted
during interpretation.
"""
function interpret(c, env, form)
  compile(c, context(env), ast.immediate(form))
end

end
