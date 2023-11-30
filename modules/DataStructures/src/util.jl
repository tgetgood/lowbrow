# Things that have nothing to do with datastructures, but expose the fact that
# I'm really implementing a new language.

struct ErrorChain
  e
  trace
end

function errorchain(e)
  ErrorChain(e, stacktrace(catch_backtrace()))
end

function handleerror(e::ErrorChain)
  showerror(stderr, e.e)
  print(stderr, "\n")
  show(stderr, "text/plain", e.trace)
  print(stderr, "\n\ncausedby\n\n")
  handleerror(e.e)
  #show(stderr, "text/plain", stacktrace(catch_backtrace()))
end

function handleerror(e)
  showerror(stderr, e)
  print(stderr, "\n")
  show(stderr, "text/plain", stacktrace(catch_backtrace()))
end
