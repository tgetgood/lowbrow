module model

import DataStructures as ds
import hardware as hw
import commands
import vertex
import Vulkan as vk

struct Vertex
  position::NTuple{3, Float32}
  colour::NTuple{3, Float32}
  texuture_coordinates::NTuple{2, Float32}
end

function vert(pos, tex)
  Vertex(tuple(pos...), (1,1,1), tuple(tex...))
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

  verticies::Vector{Vertex} = []

  for facet in get(objs, "f")
    append!(verticies, map(x -> triplev(x, vs, ts), facet))
  end

  ds.merge(
    vertex.vertexbuffer(system, verticies),
    vertex.indexbuffer(system, 0:length(verticies) - 1)
  )
end

end
