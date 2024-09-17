module Env
import DataStructures as ds

import ..Forms
import ..Receivers
import ..Eval

"""
Wraps a function so as to evaluate arguments before passing them in.
"""
function extensionalise(f::Function)
  function(args)
    coll = Receiver.Collector(length(args), f)
    System.pushngo!(Eval.mapeval(coll, args))
  end
end

# To start we're just going to use jl functions.
default = ds.hashmap(
  Forms.Keyword(["+"]), extensionalise(+),
  Forms.Keyword(["eval"]), Eval.eval,
)

end
