module DefaultEnv
import DataStructures as ds

import ..System as sys
import ..CPSCompiler as comp
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

    sys.emit(c, :env, eprime, :return, form)
  end

  comp.entry(comp.withcc(c, :return, next), lex, body)
end

function createμ(c, env, params, body)
  function next(left)
    if isa(left, ds.Symbol)
      env = comp.declare(env, left)
      next = body -> sys.succeed(c, ast.Mu(env, left, body))
    else
      next = body -> sys.succeed(c, ast.PartialMu(
        env,
        left,
        body
      ))
    end
    comp.compile(sys.withcc(c, :return, next), env, body)
  end
  comp.compile(sys.withcc(c, :return, next), env, params)
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
  ds.symbol("μ"), ast.PrimitiveMacro(createμ),

  ds.symbol("select"), ast.PrimitiveFunction(ifelse),
  ds.symbol("+*"), ast.PrimitiveFunction(+),
  ds.symbol("first*"), ast.PrimitiveFunction(first),
  ds.symbol("second*"), ast.PrimitiveFunction(second)
)

end
