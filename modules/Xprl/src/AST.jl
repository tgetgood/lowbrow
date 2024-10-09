module AST

import Base: hash, ==, string, length, getindex, eltype, show, get, iterate

import DataStructures as ds
import DataStructures: containsp, walk, emptyp, count, ireduce, first, rest

##### Dynamic Environment

abstract type Context end

struct DummyContext <: Context end
dctx = DummyContext()

struct RootContext <: Context
  lex::ds.Map
end

struct BoundContext <: Context
  parent::Context
  sym::ds.Symbol
  binding
end

struct UnboundContext <: Context
  parent::Context
  sym::ds.Symbol
end

get(c::DummyContext, _) = throw("dummy context!")

function get(c::RootContext, s)
  get(c.lex, s)
end

function get(c::BoundContext, s)
  if s == c.sym
    c.binding
  else
    get(c.parent, s)
  end
end

function get(c::UnboundContext, s)
  if s == c.sym
    throw(string(s) * " is not yet bound")
  else
    get(c.parent, s)
  end
end


containsp(c::DummyContext, _) = throw("dummy context!")
containsp(c::RootContext, s) = containsp(c.lex, s)
containsp(c::BoundContext, s) = s == c.sym || resolvedp(c.parent, s)
containsp(c::UnboundContext, s) = s != c.sym && resolvedp(c.parent, s)

unboundp(c::DummyContext, _) = throw("dummy context!")
unboundp(c::UnboundContext, s) = s == c.sym || unboundp(c.parent, s)
unboundp(c::RootContext, s) = false
unboundp(c::Context, s) = unboundp(c.parent)

lex(c::Context) = lex(c.parent)
lex(c::RootContext) = c.lex

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

struct TopLevelForm <: ds.Sexp
  # REVIEW: string/read should be an isomorphism, but I'll need to prove that if
  # hashed based caching is going to be reliable.
  #
  # There really isn't any way to get the string of a single form out of a
  # stream without reading it...
  #
  # Of course we'll lose comments and formatting, but that's actually a good
  # thing for hashing, isn't it?
  #
  # But then we'll need to read in the code text before we know whether we have
  # it cached or not...
  #
  # But then we can use the filesystem modified metadata (or source control) to
  # cache whole files.
  env::Context
  form
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

function top(env::Context, form)
  ds.prewalk(x -> setcontext(env, x), form)
end

function top(env::ds.Map, form)
  top(RootContext(env), form)
end

struct Immediate
  env::Context
  form
end

immediate(f) = immediate(dctx, f)
immediate(e, f) = Immediate(e, f)

string(f::Immediate) = "~" * string(f.form)

function show(io::IO, mime::MIME"text/plain", s::Immediate)
  print(io, string(s))
end

function walk(inner, outer, f::Immediate)
  outer(Immediate(f.env, inner(f.form)))
end

struct Pair
  env::Context
  head
  tail
end

struct ArgList
  args::Tuple
end

pair(e, h, t) = Pair(e, h, t)
pair(h, t) = pair(dctx, h, t)

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
  "#"*string(x.args)
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
  env::Context
  head
  tail
end

function Base.:(==)(x::Application, y::Application)
  x.head == y.head && x.tail == y.tail
end

const apphash = hash("#Application")

function hash(x::Application)
  xor(apphash, hash(x.head), hash(x.tail))
end

struct Mu
  env::Context
  arg::ds.Symbol
  body
end

function Base.:(==)(x::Mu, y::Mu)
  x.env == y.env && x.arg == y.arg && x.body == y.body
end

const muhash = hash("#Mu")

function hash(x::Mu)
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

end # module
