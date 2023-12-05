import graphics
import hardware as hw
import resources as rd
import framework as fw
import pipeline as gp
import render as draw
import eventsystem as es
import mouse

import DataStructures as ds
import Vulkan as vk

struct Vertex
  position::NTuple{2, Float32}
end

function vert(pos)
  Vertex(tuple(pos...))
end

function load(config)
  config = ds.update(config, :verticies, x -> map(vert, x))
  config = ds.update(config, :indicies, x -> map(UInt16, x))
  config = ds.assoc(config, :vertex_input_state, rd.vertex_input_state(Vertex))
end

prog = ds.hashmap(
  :name, "The Separator",
  :render, ds.hashmap(
    :texture_file, *(@__DIR__, "/../../assets/texture.jpg"),
    :shaders, ds.hashmap(
      :vertex, *(@__DIR__, "/../shaders/mand.vert"),
      :fragment, *(@__DIR__, "/../shaders/mand.frag")
    ),
    :inputassembly, ds.hashmap(
      :topology, :triangles
    )
  ),
  :model, ds.hashmap(
    :loader, load,
    :vertex_type, Vertex
  ),
  :verticies, [
    [-1.0f0, -1.0f0],
    [1.0f0, -1.0f0],
    [1.0f0, 1.0f0],
    [-1.0f0, 1.0f0]
  ],
  :indicies, [0, 3, 2, 2, 1, 0,]
)

function main()

  config = graphics.configure(load(prog))

  system, config = graphics.instantiate(graphics.staticinit(config), config)

  config = fw.buffers(system, config)

  graphics.renderloop(system, config) do i, renderstate
    renderstate
  end
end


es.init()

main()

drag = ds.stream(
  ds.combinelast(ds.emptymap) ∘ mouse.drag(),
  ds.interleave(es.getstreams(:click, :position))
)

zoom = ds.stream(
  mouse.zoom() ∘ map(x -> ds.update(x, :scroll, y -> y isa Tuple ? y[2] : y)),
  ds.interleave(es.getstreams(:position, :scroll))
)

function normalisezoom(z)
  exp(-z/100)
end

function recentrezoom(Δzoom, offset, zoomcentre)
  znorm = normalisezoom(Δzoom)

  (znorm .* offset) .+ ((1 - znorm) .* zoomcentre)
end

function viewframe(frame, ev)
  if ds.containsp(ev, :drag)
    ds.update(frame, :offset, .+, get(ev, :drag))
  elseif ds.containsp(ev, :scroll)
    zoom = get(frame, :zoom)
    offset = get(frame, :offset)

    Δzoom = ds.getin(ev, [:scroll, :scroll])
    zoomcentre = ds.getin(ev, [:scroll, :position])

    ds.hashmap(
      :zoom, zoom + Δzoom,
      :offset, recentrezoom(Δzoom, offset, zoomcentre)
    )
  else
    @assert false "unreachable"
  end
end

frame = ds.stream(
  ds.scan(viewframe, ds.hashmap(:zoom, 0, :offset, (0.5,0.5))),
  ds.interleave(ds.hashmap(:scroll, zoom, :drag, drag))
)

to_render = ds.subscribe(frame; buffer=1)
