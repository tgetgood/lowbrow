module DefaultEnv
import DataStructures as ds

import ..Receivers
import ..Eval

"""
Wraps a function so as to evaluate arguments before passing them in.

This needs to be converted to a struct since we don't know how to evaluate the
args at the point this is called.
"""
function argeval(f::Function)
  Eval.Applicative(f)
end

second(x) = x[2]

# To start we're just going to use jl functions.
default = ds.hashmap(
  ds.Symbol(["eval"]), Eval.eval,
  ds.Symbol(["apply"]), Eval.apply,
  ds.Symbol(["μ"]), Eval.createμ,

  ds.Symbol(["+"]), argeval(+),
  ds.Symbol(["first"]), argeval(first),
  ds.Symbol(["second"]), argeval(second)
)

end
