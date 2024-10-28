module DefaultEnv
import DataStructures as ds

import ..System as sys
import ..C6 as comp
import ..AST as ast

function def(c, env, args)
  name = args[1]

  if length(args) === 3
    docstring = args[2]
    body = args[3]
  else
    docstring = ""
    body = args[2]
  end

  function next(cform)
    meta = ds.hashmap(
        ds.keyword("env"), env,
        ds.keyword("doc"), docstring,
        ds.keyword("src"), body
    )

    eprime = ds.assoc(env, name, cform)

    sys.emit(c, :env, eprime, :return, name)
  end

  comp.eval(sys.withcc(c, :return, next), env, body)
end


function inspect(c, env, s)
  function next(f)
    ast.inspect(f)
    # FIXME: It should never be necessary to return nothing. There shouldn't be
    # a reified Nothing at all; just don't return anything.
    #
    # But right now the repl waits for messages on the return channel. This
    # wouldn't be necessary if we had a :complete handler or something of the
    # sort that lets us know when all messages that will be sent by a given
    # subunit have been sent.
    #
    # I'm not entirely sure how to implement that at the moment.
    sys.succeed(c, nothing)
  end

  comp.eval(sys.withcc(c, :return, next), env, first(s))
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
  ds.symbol("mu"), ast.PrimitiveMacro(comp.createμ),
  ds.symbol("inspect"), ast.PrimitiveMacro(inspect),

  ds.symbol("nth*"), ast.PrimitiveFunction(ds.nth),
  ds.symbol("select"), ast.PrimitiveFunction(ifelse),
  ds.symbol("+*"), ast.PrimitiveFunction(+),
  ds.symbol("-*"), ast.PrimitiveFunction(-)
)

end
