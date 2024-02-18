import DataStructures as ds
import uniform
import window
import model
import textures
import resources as rd
import framework as fw
import TaskPipelines as tp
import graphics

import Vulkan as vk

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
  ds.update(ds.update(config, :ubo, ubo),
    :render,
    merge,
    ds.assoc(model.load(config),
      :vertex_input_state, rd.vertex_input_state(model.Vertex)
    )
  )
end

##### Main definition

x = pi/3
frames = 3

"""
Static description of the program to be run. Pure data. Shouldn't invoke
anything.
"""
prog = ds.hashmap(
  :device_req, ds.hashmap(
    :features, ds.hashmap(
      v"1.0", ds.set(:sampler_anisotropy),
      v"1.2", ds.set(:timeline_semaphore),
      v"1.3", [:synchronization2]
    ),
    :extensions, ds.set("VK_KHR_swapchain")
  ),
  :model_file, *(@__DIR__, "/../../assets/viking_room.obj"),
  :texture_file, *(@__DIR__, "/../../assets/viking_room.png"),
  :concurrent_frames, frames,
  :render, ds.hashmap(
    :shaders, ds.hashmap(
      :vertex, *(@__DIR__, "/../shaders/viking.vert"),
      :fragment, *(@__DIR__, "/../shaders/viking.frag")
    ),
    :inputassembly, ds.hashmap(
      :topology, :triangles
    ),
    :descriptorsets, ds.hashmap(
      :count, frames,
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

  config = graphics.configure(load(prog))
  frames = get(config, :concurrent_frames)

  system = graphics.staticinit(config)
  dev = get(system, :device)

  texture = textures.textureimage(system, get(config, :texture_file))

  ubos = uniform.allocatebuffers(system, MVP, frames)

  dsets = fw.descriptors(
    dev,
    ds.getin(config, [:render, :descriptorsets, :bindings]),
    frames
  )

  config = ds.updatein(config, [:render, :descriptorsets], merge, dsets)

  fw.binddescriptors(
    dev,
    ds.getin(config, [:render, :descriptorsets]),
    ds.into([], map(i -> [ubos[i], texture]), 1:frames)
  )

  gconfig = fw.buffers(system, get(config, :render))

  gp = tp.graphicspipeline(system, gconfig)

  i = 0
  while true
    window.poll()

    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    i = (i % frames) + 1
    uniform.setubo!(ubos[i], timerotate(get(config, :ubo)))

    sig = take!(tp.run(gp, []))

    if sig === :closed
      break
    elseif sig === :skip
      sleep(0.08)
    end
  end
  @async tp.teardown(gp)
end

main()
