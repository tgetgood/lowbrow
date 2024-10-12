module Overrides

import DataStructures as ds
import Base.getproperty

# FIXME: Now why the fuck does this work when here when the same code in the
# DataStructures module seems to be ignored?
# UPDATE: Has this been fixed upstream?
# @inline function Base.getproperty(m::ds.PersistentArrayMap, k::Symbol)
#   if k === :kvs
#     return getfield(m, :kvs)
#   else
#     get(m, k)
#   end
# end

# @inline function Base.getproperty(m::ds.PersistentHashMap, k::Symbol)
#   if k === :root
#     return getfield(m, :root)
#   else
#     get(m, k)
#   end
# end

end
