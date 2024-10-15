module DefaultEnv
import DataStructures as ds

import ..Receivers
import ..CPSCompiler as comp
import ..Environment as E
import ..AST as ast

function def(c, env, name, args...)
  if length(args) === 2
    docstring = args[1]
    body = args[2]
  else
    docstring = ""
    body = args[1]
  end

  lex = env.env

  function next(cform)
    form = ast.TopLevel(lex, body, cform)
    eprime = ds.assoc(lex, name, form)

    comp.emit(c, :env, eprime, :return, form)
  end

  comp.entry(comp.withcc(c, :return, next), lex, body)
end

second(x) = x[2]

# TODO: There ought to be top level channels for many things
defaultchannels = ds.emptymap

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
  ds.symbol("def"), ast.PrimitiveMacro(def),
  ds.symbol("μ"), ast.PrimitiveMacro(comp.createμ),

  ds.symbol("select"), ast.PrimitiveFunction(ifelse),
  ds.symbol("+*"), ast.PrimitiveFunction(+),
  ds.symbol("first*"), ast.PrimitiveFunction(first),
  ds.symbol("second*"), ast.PrimitiveFunction(second)
)

end
