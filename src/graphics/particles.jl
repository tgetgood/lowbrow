import hardware as hw
import resources as rd
import framework as fw
import uniform
import commands
import graphics

import DataStructures as ds
import DataStructures: hashmap, into, emptyvector

import Vulkan as vk

struct Particle
  position::NTuple{2, Float32}
  velocity::NTuple{2, Float32}
  colour::NTuple{4, Float32}
end

function position(r, θ, n)
  (r*cos(θ) * n, r*sin(θ))
end

function velocity(p)
  x = p[1]
  y = p[2]

  n = sqrt(x^2+y^2)

  (25f-5/n) .* (x, y)
end

function init(count, width, height)::Vector{Particle}
  ds.into(
    ds.emptyvector,
    ds.partition(5)
    ∘
    map(x -> (sqrt(x[1]) * 25.0f-2, x[2] * 2pi, x[3:5]))
    ∘
    map(x -> (position(x[1], x[2], height / width), x[3]))
    ∘
    map(x -> Particle(x[1], velocity(x[1]), tuple(x[2]..., 1f0))),
    rand(Float32, 5, count)
  )
end

function particle_buffers(system, config)
  n = get(config, :particles)
  ext = get(system, :extent)
  particles = init(n, ext.width, ext.height)

  ssbos = into(
    emptyvector,
    map(_ -> hw.buffer(system, ds.hashmap(
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT |
              vk.BUFFER_USAGE_STORAGE_BUFFER_BIT,
      :size,  sizeof(Particle) * n,
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
      :queues, [:transfer, :graphics, :compute]
    )))
    ∘
    map(x -> ds.assoc(x, :verticies, n))
    ,
    1:get(config, :concurrent_frames)
    )

  commands.todevicelocal(system, particles, ssbos...)

  ssbos
end

prog = hashmap(
  :particles, 4096,
  :shaders, hashmap(
    :vertex, "particles.vert",
    :fragment, "particles.frag",
    # :compute, "particles.comp"
  ),
)

function main()
  config = graphics.configure(prog)

  system = graphics.staticinit(config)

  frames = get(config, :concurrent_frames)

  ### rendering

  config = ds.assoc(
    config,
    :vertex_input_state,
    rd.vertex_input_state(Particle)
  )

  ### Init graphics pipeline

  system, config = graphics.instantiate(system, config)

  ### Bound buffers

  deltas = uniform.allocatebuffers(system, Float32, frames)

  ssbos = particle_buffers(system, config)

  ### compute

  compute_layout = [
    ds.hashmap(
      :usage, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      :stage, vk.SHADER_STAGE_COMPUTE_BIT
    ),
    ds.hashmap(
      :usage, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
      :stage, vk.SHADER_STAGE_COMPUTE_BIT
    ),
    ds.hashmap(
      :usage, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
      :stage, vk.SHADER_STAGE_COMPUTE_BIT
    )
  ]

  compute_bindings = ds.map(i -> [
      deltas[i], ssbos[(i % frames) + 1], ssbos[((i + 1) % frames) + 1]
    ],
    1:frames
  )

  ### run

  t1 = time()

  graphics.renderloop(system, config) do i, renderstate
    # TODO: Some sort of framestate abstraction so that we don't have to
    # manually juggle this index.
    t2 = time()
    uniform.setubo!(deltas[i], Float32(t2-t1))
    t1 = t2

    vb = ssbos[(i % frames) + 1]

    return ds.assoc(renderstate, :vertexbuffer, vb)
  end
end

repl_teardown = main()
