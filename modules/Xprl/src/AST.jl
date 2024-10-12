module AST

import Base: hash, ==, string, length, getindex, eltype, show, get, iterate

import DataStructures as ds
import DataStructures: containsp, walk, emptyp, count, ireduce, first, rest

import ..Environment as E

##### Run time data structures

abstract type BuiltIn end

"""
Primitive functions expect their arguments to be literal values. They should
normally be wrapped to make sure args are evaluated.
"""
struct PrimitiveFunction <: BuiltIn
  f::Function
end

"""
Primitive macros operate directly on the AST of the program. They also receive
the lexical envronment when invoked.
"""
struct PrimitiveMacro <: BuiltIn
  f::Function
end

"""
Container for defined forms and those typed into the repl.
"""
struct TopLevel
  lexicalenv
  source
  compiled
end

string(x::TopLevel) = string(x.source)

function show(io::IO, mime::MIME"text/plain", s::TopLevel)
  print(io, string(s))
end

struct Immediate
  env
  form
end

immediate(f) = immediate(ds.emptymap, f)
immediate(e, f) = Immediate(e, f)

string(f::Immediate) = "~" * string(f.form)

function show(io::IO, mime::MIME"text/plain", s::Immediate)
  print(io, string(s))
end

function walk(inner, outer, f::Immediate)
  outer(Immediate(f.env, inner(f.form)))
end

struct Pair
  env
  head
  tail
end

struct ArgList
  args::Tuple
end

pair(e, h, t) = Pair(e, h, t)
pair(h, t) = pair(ds.emptymap, h, t)

function tailstring(c::ArgList)
  ds.into(" ", map(string) ∘ ds.interpose(" "), c)
end

function tailstring(x)
  " . " * string(x)
end

function string(c::Pair)
  "(" * string(c.head) * tailstring(c.tail) * ")"
end

function show(io::IO, mime::MIME"text/plain", s::Pair)
  print(io, string(s))
end

function walk(inner, outer, form::Pair)
  outer(Pair(form.env, inner(form.head), inner(form.tail)))
end

function count(x::ArgList)
  count(x.args)
end

length(x::ArgList) = count(x)

emptyp(x::ArgList) = count(x) === 0

function iterate(x::ArgList)
  iterate(x.args)
end

function iterate(x::ArgList, state)
  iterate(x.args, state)
end

function getindex(x::ArgList, n)
  getindex(x.args, n)
end

function eltype(x::ArgList)
  eltype(x.args)
end

function first(x::ArgList)
  first(x.args)
end

function rest(x::ArgList)
  x.args[2:end]
end

function ireduce(x::ArgList)
  ireduce(x.args)
end

function Base.:(==)(x::ArgList, y::ArgList)
  x.args == y.args
end

const arglistbasehash = hash("#ArgList")

function hash(x::ArgList)
  xor(arglistbasehash, hash(x.args))
end

function string(x::ArgList)
  ds.into("#(", map(string) ∘ ds.interpose(" "), x.args) * ")"
end

function show(io::IO, mime::MIME"text/plain", s::ArgList)
  print(io, string(s))
end

function arglist(xs)
  ArgList(tuple(xs...))
end

function walk(inner, outer, l::ArgList)
  outer(arglist(map(inner, l.args)))
end

"""
Represents an application of args to a function-like entity which has not been
performed yet.
"""
struct Application
  env
  head
  tail
end

function string(x::Application)
  "#Application(" * string(x.head) * ", " * string(x.tail) * ")"
end

function show(io::IO, mime::MIME"text/plain", s::Application)
  print(io, string(s))
end

function Base.:(==)(x::Application, y::Application)
  x.head == y.head && x.tail == y.tail
end

const apphash = hash("#Application")

function hash(x::Application)
  xor(apphash, hash(x.head), hash(x.tail))
end

struct Mu
  env
  arg::ds.Symbol
  body
end

string(x::Mu) = "(μ " * string(x.arg) * " " * string(x.body) * ")"

function show(io::IO, mime::MIME"text/plain", s::Mu)
  print(io, string(s))
end

function Base.:(==)(x::Mu, y::Mu)
  x.env == y.env && x.arg == y.arg && x.body == y.body
end

const muhash = hash("#Mu")

function hash(x::Mu)
  xor(muhash, hash(x.env), hash(x.arg), hash(x.body))
end

struct PartialMu
  env
  arg
  body
end

string(x::PartialMu) = "(μ " * string(x.arg) * " " * string(x.body) * ")"

function show(io::IO, mime::MIME"text/plain", s::PartialMu)
  print(io, string(s))
end

function Base.:(==)(x::PartialMu, y::PartialMu)
  x.env == y.env && x.arg == y.arg && x.body == y.body
end

const muhash = hash("#Mu")

function hash(x::PartialMu)
  xor(muhash, hash(x.env), hash(x.arg), hash(x.body))
end

"""
Returns true iff the form cannot be further reduced and contains no immediate
evaluation. (Immediate evaluation just means evaluations that cannot be done yet
but must eventually be performed).
"""
reduced(form) = true
reduced(form::Immediate) = false
reduced(form::Application) = false
reduced(form::ds.Symbol) = false
reduced(form::Pair) = reduced(form.head) && reduced(form.tail)
reduced(form::Mu) = reduced(form.arg) && reduced(form.body)
reduced(form::ArgList) = ds.every(identity, map(reduced, form.args))

function space(level)
  if level > 0
    print(repeat(" |", level))
  end
end

function inspect(form::Pair, level=0)
  space(level)
  println("P")
  inspect(form.head, level+1)
  inspect(form.tail, level+1)
end

function inspect(form::ArgList, level=0)
  space(level)
  println("L")
  for e in form.args
    inspect(e, level+1)
  end
end

function inspect(form::Immediate, level=0)
  space(level)
  println("I")
  inspect(form.form, level+1)
end

function inspect(form::ds.Symbol, level=0)
  space(level)
  println("S["*string(form)*"]")
end

function inspect(form::Application, level=0)
  space(level)
  println("A")
  inspect(form.head, level+1)
  inspect(form.tail, level+1)
end

function inspect(form::PartialMu, level=0)
  space(level)
  println("Pμ")
  inspect(form.arg, level+1)
  inspect(form.body, level+1)
end

function inspect(form::Mu, level=0)
  space(level)
  println("μ")
  inspect(form.arg, level+1)
  inspect(form.body, level+1)
end

function inspect(form::BuiltIn, level=0)
  space(level)
  println("F["*string(form)*"]")
end

function inspect(form, level=0)
  space(level)
  println("V["*string(typeof(form))*"]")
end

function inspect(form::TopLevel, level=0)
  space(level)
  println("-T-")
  inspect(form.compiled, level)
end

function setcontext(env, x)
  x
end

function setcontext(env, x::Immediate)
  Immediate(env, x.form)
end

function setcontext(env, x::Pair)
  Pair(env, x.head, x.tail)
end

"""
Takes a read but uncompiled form and replaces the lexical environment of all
nodes with the new one given thus regrounding the meaning of all symbols in the
expression.
"""
function reground(env, form)
  ds.prewalk(x -> setcontext(env, x), form)
end

function envwalk(form, _, _)
  form
end

function envwalk(form::Pair, f, s)
  Pair(f(form.env, s), envwalk(form.head, f, s), envwalk(form.tail, f, s))
end

function envwalk(form::Immediate, f, args)
  Immediate(f(form.env, args), envwalk(form.form, f, args))
end

function envwalk(form::Mu, f, args)
  # FIXME: This will not work for binding.
  if args == form.arg
    @warn "shadowing"
    # Shadowing
    form
  else
    Mu(f(form.env, args), form.arg, envwalk(form.body, f, args))
  end
end

function envwalk(form::PartialMu, f, args)
  PartialMu(
    f(form.env, args),
    envwalk(form.arg, f, args),
    envwalk(form.body, f, args)
  )
end

function envwalk(form::ArgList, f, args)
  arglist(map(x -> envwalk(x, f, args), form.args))
end

function envwalk(form::Application, f, args)
  Application(
    f(form.env, args),
    envwalk(form.head, f, args),
    envwalk(form.tail, f, args))
end

function evwalk(form::TopLevel, f, args)
  TopLevel(form.env, form.source, envwalk(form.compiled, f, args))
end

declare(form, s) = envwalk(form, E.declare, s)

function bind(form, k, v)
  envwalk(form, (e, (k, v)) -> E.bind(e, k, v), (k, v))
end

function mergelocals(env, form)
  function ml(e, env)
    e = ds.update(e, :local, merge, get(env, :local))
    ds.update(e, :unbound, ds.union, get(env, :unbound))
  end
  envwalk(form, ml, env)
end

end # module
