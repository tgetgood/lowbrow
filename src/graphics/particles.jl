import hardware as hw
import DataStructures as ds
import DataStructures: hashmap, into, emptyvector
import commands

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

function init(count, width, height)
  v::Vector{Particle} = ds.into(
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

function buffers(system, config)
  n = ds.getin(config, [:particles, :count])
  ext = get(system, :extent)
  particles = init(n, ext.width, ext.height)

  ssbos = into(
    emptyvector,
    map(_ -> hw.buffer(system, ds.hashmap(
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT |
              vk.BUFFER_USAGE_STORAGE_BUFFER_BIT,
      :size,  sizeof(Particle) * n,
      :queues, [:transfer, :graphics, :compute]
    )))
    ∘
    map(x -> ds.assoc(x,
      :layout_type, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
      :eltype, Particle

    )),
    1:get(config, :concurrent_frames)
    )

  commands.todevicelocal(system, particles, ssbos...)

  # TODO: Use a push constant here.
  ubo = hw.buffer(system, ds.hashmap(
    :size, sizeof(Float64),
    :usage, vk.BUFFER_USAGE_UNIFORM_BUFFER_BIT,
    :queues, [:compute],
    :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                  vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
  ))

  memptr = Ptr{Float64}(vk.unwrap(vk.map_memory(
          get(system, :device), get(ubo, :memory), 0, get(ubo, :size)
  )))

  ubometa = ds.assoc(ubo,
    :eltype, Float64,
    :layout_type, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
    :memptr, memptr
  )

  hashmap(:particle_buffers, into(ds.vec(ubometa), ssbos))
end
