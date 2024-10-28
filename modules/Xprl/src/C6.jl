module C6

import Base: string

import DataStructures as ds
import ..System as sys
import ..AST as ast
import ..AST: inspect

##### Env during compile

struct ContextSwitch
  env::ds.Map
  body
end

string(x::ContextSwitch) = "#ContextSwitch"

function show(io::IO, mime::MIME"text/plain", s::ContextSwitch)
  print(io, string(s))
end

inspect(x::ContextSwitch) = inspect(x.body)

function extendin(outer, inner, bindings)
  ds.into(
    outer,
    map(e -> (ds.key(e), ContextSwitch(inner, ds.val(e)))),
    bindings
  )
end

##### Destructuring

"""
Returns true iff an expression is a valid left side of a destructured bind.

FIXME: Only symbols and vectors are currently supported.
"""
structuredbindp(x) = false
structuredbindp(x::ds.Symbol) = true
structuredbindp(xs::ds.Vector) = ds.every(structuredbindp, xs)

bindings(x) = []
bindings(x::ds.Symbol) = [x]
bindings(x::ds.Vector) = ds.into!([], map(bindings) ∘ ds.cat(), x)

# FIXME: Maps!
function destructuringbind(x, y)
  @warn "incompatible sexps in destructuring."
  :bindfailure
end

destructuringbind(x::ds.Symbol, y::Any) = ds.hashmap(x, y)

function destructuringbind(xs::ds.Vector, ys::ds.Vector)
  @assert ds.count(xs) == ds.count(ys) "Invalid destructure."
  ds.reduce(
    ds.merge,
    ds.map(destructuringbind, xs, ys)
  )
end

##### μs are more special than I like.

function createμ(c, env, args)
  args = args
  params = args[1]
  body = args[2]
  function next(left)
    if structuredbindp(left)
      innerenv = ds.reduce(ds.dissoc, env, bindings(left))

      next = cbody -> sys.succeed(c, ast.Mu(env, body, left, cbody))
      compile(sys.withcc(c, :return, next), innerenv, body)
    else
      sys.succeed(c, ast.PartialMu(left, body))
    end
  end
  compile(sys.withcc(c, :return, next), env, params)
end

##### Helpers

wrt(c, n) = sys.withcc(c, :return, n)

##### Eval

function eval(c, env, f::ContextSwitch)
  eval(c, f.env, f.body)
end

function eval(c, env, s::ds.Symbol)
  v = get(env, s, :notfound)
  if v === :notfound
    sys.succeed(c, ast.Immediate(s))
  else
    compile(c, env, v)
  end
end

function eval(c, env, f::ast.Immediate)
  next(x::ast.Immediate) = sys.succeed(c, ast.immediate(x))
  next(x) = eval(c, env, x)
  compile(wrt(c, next), env, f)
end

function eval(c, env, f::ast.Pair)
  compile(c, env, ast.Application(ast.Immediate(f.head), f.tail))
end

function eval(c, env, f::ds.Vector)
  compile(c, env, map(x -> ast.immediate(x), f))
end

function eval(c, env, f)
  # @warn "eval fallthrough: " * string(typeof(f))
  sys.succeed(c, f)
end

##### Apply

# Delay
function apply(c, env, f::ast.Immediate, tail)
  sys.succeed(c, ast.Application(f, tail))
end

function apply(c, env, f::ast.Application, tail)
  next(x::ast.Application) = sys.succeed(c, ast.Application(x, tail))
  next(x) = apply(c, env, x, tail)
  compile(wrt(c, next), env, f)
end

function apply(c, env, f::ast.Mu, tail)
  function next(tail)
    bindings = destructuringbind(f.params, tail)
    if bindings === :bindfailure
      sys.succeed(c, ast.Application(f, tail))
    else
      innerenv = extendin(f.env, env, bindings)
      compile(c, innerenv, f.body)
    end
  end
  compile(wrt(c, next), env, tail)
end

function apply(c, env, f::ast.PartialMu, tail)
  sys.succeed(c, ast.Application(f, tail))
end

function apply(c, env, f::ast.PrimitiveMacro, tail)
  f.f(c, env, tail)
end

function apply(c, env, f::ast.PrimitiveFunction, tail)
  function next(tail)
    if ast.reduced(tail)
      sys.succeed(c, f.f(tail...))
    else
      sys.succeed(c, ast.Application(f, tail))
    end
  end
  # The contract of a primitive function is that when it is applied, the right
  # hand side will be compiled before the external function is called.
  #
  # Phrased differently, primitive functions are interpreters in *other*
  # languages to which we can send and from which we can receive ~literal
  # values~.
  #
  # Since these external computers cannot understand our syntax, we need to
  # compile it away to values before sending messages.
  compile(wrt(c, next), env, tail)
end

##### Compile

function compile(c, env, f::ast.Immediate)
  eval(c, env, f.form)
end

function compile(c, env, f::ast.Application)
  next(head) = apply(c, env, head, f.tail)
  compile(wrt(c, next), env, f.head)
end

function compile(c, env, f::ast.PartialMu)
  createμ(c, env, [f.params, f.body])
end

function compile(c, env, f::ast.Mu)
  createμ(c, env, [f.params, f.body])
end

function compile(c, env, f::ds.Vector)
  coll = sys.collector(wrt(c, x -> sys.succeed(c, x)), ds.count(f))

  function runner((i, f))
    compile(wrt(c, x -> sys.receive(coll, i, x)), env, f)
  end

  tasks = ds.into(
    ds.emptyvector,
    ds.interleave(),
    ds.repeat(:run),
    ds.mapindexed(tuple, f)
  )

  sys.emit(sys.withcc(c, :run, runner), tasks...)
end

function compile(c, env, f::ContextSwitch)
  compile(c, f.env, f.body)
end

function compile(c, env, f)
  # @warn "compile fallthrough: " * string(typeof(f))
  sys.succeed(c, f)
end

##### Entry

function interpret(c, env, f)
  compile(c, env, ast.Immediate(f))
end

end # module
