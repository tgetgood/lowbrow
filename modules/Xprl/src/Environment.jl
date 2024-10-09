module Environment

import Base: hash, ==, string, show, get

import DataStructures as ds
import DataStructures: containsp

# TODO: ==, hash, string for environments

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

function extend(m::ds.Map, k, v)
  ds.assoc(m, k, v)
end

function extend(m::UnboundContext, k, v)
  if k == m.sym
    BoundContext(m.parent, k, v)
  else
    UnboundContext(extend(m.parent, k, v), m.sym)
  end
end


end # module
