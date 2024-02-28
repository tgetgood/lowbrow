module Helpers

import DataStructures as ds

"""
Takes a function and args and applies it in a thread, returning a channel which
will eventually yield the result.
"""
function thread(f, args...; name="")
  join = Channel()
  Threads.@spawn begin
      try
        put!(join, f(args...))
      catch e
        @error "Error in thread " * name
        ds.handleerror(e)
      end
  end
  return join
end

end
