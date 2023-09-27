module model

import DataStructures as ds
import hardware as hw
import commands
import vertex
import Vulkan as vk

struct Vertex
  position::NTuple{3, Float32}
  texuture_coordinates::NTuple{2, Float32}
end

function vert(pos, tex)
  Vertex(tuple(pos...), tuple(tex...))
end

function typesort(lines)
  res = ds.emptymap
  for line in lines
    s = split(line, " ")
    tag = first(s)
    val = ds.rest(s)
    if ds.containsp(res, tag)
      push!(get(res, tag), val)
    else
      res = ds.assoc(res, tag, [val])
    end
  end
  return res
end

function tofloat(v)
  map(x -> map(y -> parse(Float32, y), x), v)
end

function triplev(f, vs, ts)
  t = map(x -> parse(Int, x), split(f, "/"))
  tex = ts[t[2]]
  vert(vs[t[1]], (1f0-tex[2], tex[1]))
end

function load(system, config)
  filename = get(config, :model_file)

  objs = typesort(eachline(filename))

  vs = tofloat(get(objs, "v"))
  ts = tofloat(get(objs, "vt"))

  vmap::ds.Map = ds.emptymap
  indicies::ds.Vector = ds.emptyvector


  for facet in get(objs, "f")
    fs = map(x -> triplev(x, vs, ts), facet)
    for f in fs
      if ds.containsp(vmap, f)
        indicies = ds.conj(indicies, get(vmap, f))
      else
        n = ds.count(vmap)
        vmap = ds.assoc(vmap, f, n)
        indicies = ds.conj(indicies, n)
      end
    end
  end

  verticies = Vector{Vertex}(undef, ds.count(vmap))
  for e in ds.seq(vmap)
    verticies[ds.val(e)+1] = ds.key(e)
  end

  ds.merge(
    vertex.vertexbuffer(system, verticies),
    vertex.indexbuffer(system, ds.into(Vector{UInt}(), indicies))
  )
end

end