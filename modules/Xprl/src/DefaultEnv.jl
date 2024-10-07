module DefaultEnv
import DataStructures as ds

import ..Receivers
import ..Eval
import ..Runtime as rt

"""
Wraps a function so as to evaluate arguments before passing them in.

This needs to be converted to a struct since we don't know how to evaluate the
args at the point this is called.
"""
function argeval(f::Function)
  Eval.Applicative(f)
end

function createμ(env, params, body)
  rt.Mu(params, Eval.compile(env, body))
end

function def(env, name, args...)
  if length(args) === 2
    docstring = args[1]
    body = args[2]
  else
    docstring = ""
    body = args[1]
  end

  form = Eval.eval(env, body)
  e2 = ds.assoc(env, name, form)

  # emit :env e2, :return form

  form
end

second(x) = x[2]

# To start we're just going to use jl functions.
default = ds.hashmap(
  ds.Symbol(["eval"]), Eval.eval,
  ds.Symbol(["apply"]), Eval.apply,
  ds.Symbol(["def"]), Eval.PrimitiveMacro(def),
  ds.Symbol(["μ"]), Eval.PrimitiveMacro(createμ),

  ds.Symbol(["+"]), Eval.PrimitiveFunction(+),
  ds.Symbol(["first"]), Eval.PrimitiveFunction(first),
  ds.Symbol(["second"]), Eval.PrimitiveFunction(second)
)

end
