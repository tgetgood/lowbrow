module mouse

import DataStructures as ds

function drag()
  started = false
  lastpos = (0f0,0f0)
  function(emit)
    function inner()
      emit()
    end
    function inner(result)
      emit(result)
    end
    function inner(result, click, pos)
      if get(click, :button) === :left
        if get(click, :action) === :down
          if started
            p = lastpos
            lastpos = pos
            emit(result, ds.hashmap(:delta, p .- pos))
          else
            lastpos = pos
            started = true
          end
        else
          if started
            started = false
            p = lastpos
            lastpos = pos
            emit(result, ds.hashmap(:delta, p .- pos))
          else
          end
        end
      end
    end
  end
end


end # module
