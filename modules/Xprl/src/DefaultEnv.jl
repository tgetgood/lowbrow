module DefaultEnv
import DataStructures as ds

import ..System as sys
import ..Interpreter as rt
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

  rt.eval(sys.withcc(c, :return, next), env, body)
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

  rt.eval(sys.withcc(c, :return, next), env, first(s))
end

function emit(c, env, args)
  if length(args) > 1
    for (ch, val) in ds.partition(2, args)
      # Now this ought to work, but I don't trust the dynamics yet.
      rt.compile(sys.withcc(c, :return, x -> sys.emit(c, x, val)), env, ch)
    end
  end
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
  ds.symbol("μ"), ast.PrimitiveMacro(rt.createμ),

  # HACK: This really shouldn't be necessary, but my repl is running in the
  # julia repl which is running in an emacs term-mode window which leads to some
  # degradation in usability.
  ds.symbol("mu"), ast.PrimitiveMacro(rt.createμ),
  ds.symbol("emit"), ast.PrimitiveMacro(emit),

  # REVIEW: This is really just for debugging right now.
  ds.symbol("inspect"), ast.PrimitiveMacro(inspect),

  ds.symbol("nth*"), ast.PrimitiveFunction(ds.nth),
  # In 3-lisp `select` was called `ef` for "extensionally defined if".
  # Notice how it's a function and not a macro.
  ds.symbol("select"), ast.PrimitiveFunction(ifelse),
  ds.symbol("+*"), ast.PrimitiveFunction(+),
  ds.symbol("-*"), ast.PrimitiveFunction(-),
  ds.symbol("**"), ast.PrimitiveFunction(*),
  ds.symbol("/*"), ast.PrimitiveFunction(/),
  ds.symbol("<*"), ast.PrimitiveFunction(<),
  ds.symbol(">*"), ast.PrimitiveFunction(>),
  ds.symbol("=*"), ast.PrimitiveFunction(==),
)

end
