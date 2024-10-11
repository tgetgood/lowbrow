module Environment

import Base: hash, ==, string, show

import DataStructures as ds

function create(lex::ds.Map)
  ds.hashmap(:lexical, lex, :local, ds.emptymap, :unbound, ds.emptyset)
end

lexical(env) = ds.get(env, :lexical)
unbound(env) = ds.get(env, :unbound)

function containsp(env, s)
  ds.containsp(ds.get(env, :local), s) || ds.containsp(ds.get(env, :lexical), s)
end

function unboundp(env, s)
  ds.containsp(unbound(env), s)
end

function get(env, s, notfound)
  if unboundp(env, s)
    notfound
  elseif ds.containsp(ds.get(env, :local), s)
    ds.getin(env, [:local, s])
  elseif ds.containsp(ds.get(env, :lexical), s)
    ds.getin(env, [:lexical, s])
  else
    notfound
  end
end

function declare(env, s)
  ds.update(env, :unbound, ds.conj, s)
end

function bind(m::ds.Map, k, v)
  if unboundp(m, k)
    ds.update(ds.associn(m, [:local, k], v), :unbound, ds.disj, k)
  else
    throw("Cannot bind value to undeclared name " * string(k))
  end
end

function extendlexical(m::ds.Map, k, v)
  ds.associn(m, [:lexical, k], v)
end

end # module
