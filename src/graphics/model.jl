module model

import DataStructures as ds
import Vulkan as vk

struct Vertex
  position::NTuple{3, Float32}
  texuture_coordinates::NTuple{2, Float32}
end

function vert(pos, tex)
  Vertex(tuple(pos...), tuple(tex...))
end

fnil(f, default) = (acc, x) -> x === nothing ? f(acc, default) : f(acc, x)

function typesort(lines)
  res = ds.emptymap
  for line in lines
    s = split(line, " ")
    tag = first(s)
    val = ds.rest(s)
    res = ds.update(res, tag, fnil(ds.conj, ds.emptyvector), val)
  end
  return res
end

function tofloat(v)
  map(x -> map(y -> parse(Float32, y), x), v)
end

function triplev(f, vs, ts)
  t = map(x -> parse(Int, x), f)
  tex = ts[t[2]]
  vert(vs[t[1]], (1f0-tex[2], tex[1]))
end

function gather((vmap, indicies), f)
  if ds.containsp(vmap, f)
    (vmap, ds.conj(indicies, get(vmap, f)))
  else
    n = ds.count(vmap)
    (ds.assoc(vmap, f, n), ds.conj(indicies, n))
  end
end
gather(x) = x

function load(filename)
  objs = typesort(eachline(filename))

  vs = tofloat(get(objs, "v"))
  ts = tofloat(get(objs, "vt"))

  (vmap, indicies::Vector{UInt}) = ds.transduce(
    ds.cat()
    ∘
    map(x -> split(x, "/"))
    ∘
    map(x -> triplev(x, vs, ts))
    ,
    gather,
    (ds.emptymap, ds.emptyvector),
    get(objs, "f")
  )

  verticies = Vector{Vertex}(undef, ds.count(vmap))

  for e in ds.seq(vmap)
    verticies[ds.val(e)+1] = ds.key(e)
  end

  ds.hashmap(:verticies, verticies, :indicies, indicies)
end

end
