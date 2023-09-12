module uniform

import Vulkan as vk

import DataStructures as ds
import hardware as hw

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

function pack(x::MVP)
  vcat(x.model..., x.view..., x.projection...)
end

function configure(config)
  ds.update(config, :ubo, ubo)
end

function allocatebuffers(system, config)
  ds.hashmap(
    :uniformbuffers,
    ds.into(
      [],
      map(_ -> hw.buffer(system, ds.hashmap(
        :size, sizeof(MVP),
        :usage, vk.BUFFER_USAGE_UNIFORM_BUFFER_BIT,
        :mode, vk.SHARING_MODE_EXCLUSIVE,
        :queues, [:graphics],
        :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                      vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
      )))
      ∘ map(x -> ds.assoc(x,
        :memptr, Ptr{Float32}(vk.unwrap(vk.map_memory(
          get(system, :device), get(x, :memory), 0, get(x, :size)
        )))
      )),
      1:get(config, :concurrent_frames)
    )
  )
end

function allocatesets(system, config)
  layout = vk.unwrap(vk.create_descriptor_set_layout(
    get(system, :device),
    [vk.DescriptorSetLayoutBinding(
      0,
      vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      vk.SHADER_STAGE_VERTEX_BIT;
      descriptor_count=1
    )]
  ))

  dsets = vk.unwrap(vk.allocate_descriptor_sets(
    get(system, :device),
    vk.DescriptorSetAllocateInfo(
      get(system, :descriptorpool),
      repeat([layout], outer=get(config, :concurrent_frames))
    )
  ))

  writes = map(x -> vk.WriteDescriptorSet(
      x[1],
      0,
      0,
      vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
      [],
      [vk.DescriptorBufferInfo(0, get(x[2], :size); buffer=get(x[2], :buffer))],
      []
    ),
    zip(dsets, get(system, :uniformbuffers))
  )

  ds.hashmap(
    :ubo, ds.hashmap(
      :descriptorsetlayout, layout,
      :descriptorsets, dsets,
      :writes, writes
    )
  )
end

function setubo!(config, buffer)
  u = get(config, :ubo)
  t = time()
  c = cos(t)
  s = sin(t)
  p::Matrix{Float32} = [
    c 0 s 0
    0 1 0 0
    -s 0 c 0.6
    0 0 0 1

    # cos(t) -sin(t) 0 0
    # sin(t) cos(t) 0 0
    # 0 0 1 0.4
    # 0 0 0 1
  ]

  u2 = MVP(u.model, u.view, tuple(p...))

  unsafe_copyto!(get(buffer, :memptr), pointer(pack(u2)), 64)
end

end
