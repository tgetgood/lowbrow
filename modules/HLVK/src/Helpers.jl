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

"""
Returns a hashmap isomorphic to s. It's probably better to override fns for
vk.HighLevelStruct to treat them like maps, rather than actually cast
everything.
"""
function srecord(s::T) where T
  ds.into(ds.emptymap, map(k -> (k, getproperty(s, k))), fieldnames(T))
end

"""
Returns a relation corresponding to a vk Vector of structs.
"""
function xrel(s::Vector{T}) where T
  ds.into(ds.emptyset, map(srecord), s)
end

end
