import UI.Glfw as window

import HLVK.uniform
import HLVK.model
import HLVK.vertex
import HLVK.textures
import HLVK.TaskPipelines as tp
import HLVK.init

import DataStructures as ds

##### Projection Uniform Buffer Object

struct MVP
  model::NTuple{16,Float32}
  view::NTuple{16,Float32}
  projection::NTuple{16,Float32}
end

function ubo(x)
  MVP(
    tuple(get(x, :model)...),
    tuple(get(x, :view)...),
    tuple(get(x, :projection)...)
  )
end

function configureprojection(config)
  ds.update(config, :ubo, ubo)
end

function timerotate(u)
  t = time() / 2
  c = cos(t)
  s = sin(t)

  p::Matrix{Float32} = [
    c 0 s 0
    0 1 0 0
    -s 0 c 0.6
    0 0 0 1
  ]

  MVP(u.model, u.view, tuple(p...))
end

function load(config)
  ds.update(config, :ubo, ubo)
end

##### Main definition

x = pi/3

"""
Static description of the program to be run. Pure data. Shouldn't invoke
anything.
"""
prog = ds.hashmap(
  :name, "viking-room",
  :version, v"0.2.0",
  :device, ds.hashmap(
    :features, ds.hashmap(
      v"1.0", ds.set(:sampler_anisotropy),
      v"1.2", ds.set(:timeline_semaphore),
      v"1.3", [:synchronization2]
    ),
    :extensions, ds.set("VK_KHR_swapchain")
  ),
  :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
  :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
  :pipelines, ds.hashmap(
    :render, ds.hashmap(
      :vertex, ds.hashmap(:type, model.Vertex),
      :shaders, ds.hashmap(
        :vertex, *(@__DIR__, "/../shaders/viking.vert"),
        :fragment, *(@__DIR__, "/../shaders/viking.frag")
      ),
      :inputassembly, ds.hashmap(
        :topology, :triangles
      ),
      :bindings, [
        ds.hashmap(
          :type, :uniform,
          :stage, :vertex
        ),
        ds.hashmap(
          :type, :combined_sampler,
          :stage, :fragment
        )
      ]
    )
  ),
  :ubo, ds.hashmap(
    :model, [
      1 0 0 0
      0 1 0 0
      0 0 1 0
      0 0 0 1
    ],
    :view, [
      1 0 0 0
      0 cos(x) -sin(x) 0
      0 sin(x) cos(x) 0
      0 0 0 1
    ],
    :projection, [
      1 0 0 0
      0 1 0 0
      0 0 1 0
      0 0 0 1
    ]
  )
)

function main()
  window.shutdown()

  system, config = init.setup(load(prog), window)
  dev = system.device
  frames = system.spec.swapchain.images

  pipelines = tp.buildpipelines(system, config)

  system = ds.assoc(system, :pipelines, pipelines)

  texture = textures.textureimage(system, get(config, :texture_file))

  ubos = uniform.allocatebuffers(system, MVP, frames)

  bindings = map(x -> [x, texture], ubos)

  graphics = system.pipelines.render

  vb, ib = vertex.buffers(system, model.load(config)...)

  renderstate = ds.hashmap(
    :vertexbuffer, vb,
    :indexbuffer, ib
  )

  i = 0
  while true
    window.poll()

    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    i = (i % frames) + 1

    uniform.setubo!(ubos[i], timerotate(get(config, :ubo)))

    sig = take!(tp.run(graphics, ds.assoc(renderstate, :bindings, bindings[i])))

    if sig === :closed
      break
    elseif sig === :skip
      sleep(0.08)
    end
  end

  window.shutdown()
  tp.teardown(graphics)
end

main()
