module DefaultEnv
import DataStructures as ds

import ..Forms
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
  Forms.Symbol(["eval"]), Eval.eval,
  Forms.Symbol(["apply"]), Eval.apply,
  Forms.Symbol(["μ"]), Eval.createμ,

  Forms.Symbol(["+"]), argeval(+),
  Forms.Symbol(["first"]), argeval(first),
  Forms.Symbol(["second"]), argeval(second)
)

end
