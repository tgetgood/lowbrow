module DefaultEnv
import DataStructures as ds

import ..Receivers
import ..Compiler: compile
import ..AST as ast

function createμ(env, params, body)
  left = Eval.compilestar(env, params)
  if isa(left, ds.Symbol)
    e = rt.MuBody(env, ds.set(left))
  else
    e = rt.UnknownContext
  end
  rt.Mu(left, Eval.compile(e, body))
end

function def(env, name, args...)
  if length(args) === 2
    docstring = args[1]
    body = args[2]
  else
    docstring = ""
    body = args[1]
  end

  form = compile(ast.top(env, body))
  # e2 = ds.assoc(env, name, form)

  # emit :env e2, :return form
end

second(x) = x[2]

default = ds.hashmap(
  # REVIEW: It seems to me (at the moment) that neither apply nor eval should be
  # available in the language. You can always evaluate a constructed expression
  # with the `~` syntax and apply an arbitrary argument to a thing with the ( .
  # ) syntax.
  #
  # Both of these avoid requiring us to make the environment manipulable, which
  # my gut tells me we'll be happy we did.
  # ds.Symbol(["eval"]), Eval.eval,
  # ds.Symbol(["apply"]), Eval.apply,
  ds.Symbol(["def"]), ast.PrimitiveMacro(def),
  ds.Symbol(["μ"]), ast.PrimitiveMacro(createμ),

  ds.Symbol(["+*"]), ast.PrimitiveFunction(+),
  ds.Symbol(["first*"]), ast.PrimitiveFunction(first),
  ds.Symbol(["second*"]), ast.PrimitiveFunction(second)
)

end
