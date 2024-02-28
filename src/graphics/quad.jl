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
  ds.updatein(config, [:pipelines, :render],
    x -> ds.assoc(x,
      :verticies, map(vert, x.verticies),
      :indicies, map(UInt16, x.indicies),
      :vertex_input_state, rd.vertex_input_state(Vertex)
    )
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
      :samples, 4,
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
  window.shutdown()
  system, config = init.setup(load(prog), window)

  pipelines = tp.buildpipelines(system, config)

  vertexbuffer, indexbuffer = vertex.buffers(
    system,
    prog.pipelines.render.verticies,
    prog.pipelines.render.indicies
  )

  gp = pipelines.render

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

main()
