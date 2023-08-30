module vertex

import DataStructures as ds
import hardware as hw
import Vulkan as vk

struct Vertex
  position::NTuple{2, Float32}
  colour::NTuple{3, Float32}
end

function vert(pos, colour)
  Vertex(tuple(pos...), tuple(colour...))
end

function verticies(xs)::Vector{Vertex}
  ds.into([], map(x -> vert(x...)), xs)
end

function buffer(system, config)
  data = get(config, :vertex_data)

  staging = hw.buffer(
    system,
    ds.assoc(
      config,
      :size, sizeof(data),
      :usage, vk.BUFFER_USAGE_TRANSFER_SRC_BIT,
      :mode, vk.SHARING_MODE_EXCLUSIVE,
      :queue, :graphics,
      :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                    vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
    )
  )

  memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
    get(system, :device), get(staging, :memory), 0, sizeof(data)
  ))

  unsafe_copyto!(memptr, pointer(data), length(data))

  # I'm guessing unsafe_copyto! just does:
  # ccall(
  #   :memcpy, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
  #   memptr, pointer(data), sizeof(data)
  # )

  vk.unmap_memory(get(system, :device), get(staging, :memory))

  buffer = hw.buffer(
    system,
    ds.hashmap(
      :size, sizeof(data),
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT,
      :mode, vk.SHARING_MODE_EXCLUSIVE,
      :queue, :graphics,
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    )
  )

  hw.copybuffer(
    system,
    get(staging, :buffer),
    get(buffer, :buffer),
    get(staging, :size),
    :graphics
  )

  ds.hashmap(:vertexbuffer, ds.assoc(buffer, :verticies, length(data)))
end

function configure(config)
  ds.update(config, :vertex_data, verticies)
end

end # module
