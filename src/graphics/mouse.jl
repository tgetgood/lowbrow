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
    function inner(result, next)
      click = get(next, :click)
      pos = get(next, :position)
      if get(click, :button) === :left
        if get(click, :action) === :down
          if started
            p = lastpos
            lastpos = pos
            emit(result, pos .- p)
          else
            lastpos = pos
            started = true
          end
        else
          if started
            started = false
            p = lastpos
            lastpos = pos
            emit(result, pos .- p)
          else
          end
        end
      end
    end
  end
end

function zoom()
  position = (0,0)
  function(emit)
    function inner()
      emit()
    end
    function inner(x)
      emit(x)
    end
    function inner(result, next)
      if ds.containsp(next, :position)
        position = get(next, :position)
      elseif ds.containsp(next, :scroll)
        emit(result, ds.assoc(next, :position, position))
      else
        @assert false "unreachable"
      end
    end
  end
end

# My cryptic code from five years ago to zoom based on mouse scrolling.

# (defn normalise-zoom [dz]
#   (let [scale 100]
#     (math/exp (/ (- dz) scale))))

# (defn zoom-c [dz ox zx]
#   (let [dz (normalise-zoom dz)]
#     (+ (* dz ox) (* zx (- 1 dz)))))

# (defn update-zoom [{z :zoom o :offset :as w} zc dz]
#   (assoc w
#          :zoom (max -8000 (min 8000 (+ z dz)))
#          :offset (mapv (partial zoom-c dz) o zc)))


end # module
