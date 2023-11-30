module eventsystem

import DataStructures as ds

const streams = ds.Atom(ds.emptymap)

function init()
  ds.reset!(streams, ds.hashmap(
    :click, ds.pub(),
    :position, ds.pub(),
    :scroll, ds.pub()
  ))
end

function send!(ev, value)
  put!(get(ds.deref(streams), ev), value)
end

function getstream(name)
  get(ds.deref(streams), name)
end

function getstreams(names...)
  ds.into(ds.emptymap, map(k -> (k, get(ds.deref(streams), k))), names)
end

function mousepositionupdate(x::Float64, y::Float64)
  send!(:position, (x, y))
end

function mouseclickupdate(event)
  send!(:click, event)
end

function mousescrollupdate(x::Float64, y::Float64)
  send!(:scroll, (x, y))
end

end
