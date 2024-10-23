module DefaultEnv
import DataStructures as ds

import ..System as sys
import ..C4 as comp
import ..AST as ast

function def(c, args)
  args = args.form
  name = args[1].form

  if length(args) === 3
    docstring = args[2].form
    body = args[3]
  else
    docstring = ""
    body = args[2]
  end

  lex = body.env

  function next(cform)
    tl = ast.TopLevel(
      ds.hashmap(
        ds.keyword("env"), lex,
        ds.keyword("doc"), docstring,
        ds.keyword("src"), body
      ),
      cform
    )

    eprime = ds.assoc(lex, name, tl)

    sys.emit(c, :env, eprime, :return, tl)
  end

  comp.eval(sys.withcc(c, :return, next), body)
end

function createμ(c, args)
  env = args.env
  args = args.form
  params = args[1]
  body = args[2]
  function next(left)
    if isa(left.form, ds.Symbol)
      body = comp.declare(body, left.form)
      next = body -> sys.succeed(c, comp.context(env, ast.Mu(left.form, body)))
    else
      @info "pm cons", string(body.unbound)
      ast.inspect(body)
      function next(body)
        @info "pm body"
        ast.inspect(body)
        sys.succeed(c, comp.context(env, ast.PartialMu(
          left,
          body
        )))
      end
    end
    comp.compile(sys.withcc(c, :return, next), body)
  end
  comp.compile(sys.withcc(c, :return, next), params)
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
  ds.symbol("second*"), ast.PrimitiveFunction(second),
  ds.symbol("nth*"), ast.PrimitiveFunction(ds.nth)
)

end
