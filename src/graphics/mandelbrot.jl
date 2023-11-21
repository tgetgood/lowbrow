import graphics
import hardware as hw
import resources as rd
import framework as fw
import pipeline as gp
import render as draw

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

  # buffers = get(system, :commandbuffers)

  # renderstate = fw.assemblerender(system, config)

  # draw.draw(system, buffers[1], renderstate)

  graphics.renderloop(system, config) do i, renderstate
    renderstate
  end
end

main()
 # r = 1.0-(c>>16)/255;
 # g = 1.0-((c&((1<<16) - 1))>>8)/255;
 # b = 1.0-(c&255)/255;
