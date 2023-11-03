##### Simple rendered quadrilateral example.

import graphics

import resources as rd
import framework as fw
import vertex

import DataStructures as ds
import Vulkan as vk


struct Vertex
  position::NTuple{3, Float32}
  colour::NTuple{3, Float32}
end

function vert((pos, colour))
  Vertex(tuple(pos...), tuple(colour...))
end

function load(config)
  config = ds.update(config, :verticies, x -> map(vert, x))
  config = ds.update(config, :indicies, x -> map(UInt16, x))
  config = ds.assoc(config, :vertex_input_state, rd.vertex_input_state(Vertex))
end

prog = ds.hashmap(
  :name, "Quad",
  :shaders, ds.hashmap(
    :vertex, "quad.vert",
    :fragment, "quad.frag"
  ),
  :model, ds.hashmap(
    :loader, load,
    :vertex_type, Vertex
  ),
  :verticies, [
    [[-0.6, -0.6, 0.3], [1, 0, 0]],
    [[0.5, -0.5, 0.3], [0, 1, 0]],
    [[0.3, 0.3, 0.3], [0, 0, 1]],
    [[-0.5, 0.5, 0.3], [0.5, 0.5, 0.5]]
  ],
  :indicies, [0, 3, 2, 2, 1, 0,]
)

function main()
  state = graphics.configure(load(prog))

  system, state = graphics.instantiate(graphics.staticinit(state), state)

  state = fw.buffers(system, state)

  graphics.renderloop(system, state) do i, renderstate
    renderstate
  end
end

repl_teardown = main()
