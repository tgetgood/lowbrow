##### Simple rendered quadrilateral example.

import init

import Glfw as window
import resources as rd
import vertex
import TaskPipelines as tp

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
  config = ds.updatein(config, [:render, :verticies], x -> map(vert, x))
  config = ds.updatein(config, [:render, :indicies], x -> map(UInt16, x))
  config = ds.associn(config,
    [:render, :vertex_input_state], rd.vertex_input_state(Vertex)
  )
end

prog = ds.hashmap(
  :name, "Quad",
  :pipelines, ds.hashmap(
    :render, ds.hashmap(
      :shaders, ds.hashmap(
        :vertex, *(@__DIR__, "/../shaders/quad.vert"),
        :fragment, *(@__DIR__, "/../shaders/quad.frag")
      ),
      :msaa, 4,
      :inputassembly, ds.hashmap(
        :topology, :triangles
      ),
      :verticies, [
        [[-0.6, -0.6, 0.3], [1, 0, 0]],
        [[0.5, -0.5, 0.3], [0, 1, 0]],
        [[0.3, 0.3, 0.3], [0, 0, 1]],
        [[-0.5, 0.5, 0.3], [0.5, 0.5, 0.5]]
      ],
      :indicies, [0, 3, 2, 2, 1, 0,])
  ),
  :model, ds.hashmap(
    :loader, load,
    :vertex_type, Vertex
  )
)

function main()
  # config = graphics.configure(load(prog))

  window.shutdown()
  system, config = init.setup(prog, window)
  dev = system.device

  vertexbuffer, indexbuffer = vertex.buffers(
    system,
    prog.pipelines.render.verticies,
    prog.pipelines.render.indicies
  )

  gp = tp.graphicspipeline(system, config)

  while true
    window.poll()
    sig = take!(tp.run(gp, []))

    if sig === :closed
      break
    elseif sig === :skip
      sleep(0.08)
    end
  end
  window.shutdown()
  tp.teardown(gp)
end

# main()
