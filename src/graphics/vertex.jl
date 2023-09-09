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

function vertexbuffer(system, config)
  data = get(config, :vertex_data)

  staging = hw.transferbuffer(system, sizeof(data))

  memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
    get(system, :device), get(staging, :memory), 0, sizeof(data)
  ))

  unsafe_copyto!(memptr, pointer(data), length(data))

  vk.unmap_memory(get(system, :device), get(staging, :memory))

  buffer = hw.buffer(
    system,
    ds.hashmap(
      :size, sizeof(data),
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT,
      :mode, vk.SHARING_MODE_CONCURRENT,
      :queues, [:graphics, :transfer],
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    )
  )

  hw.copybuffer(
    system,
    get(staging, :buffer),
    get(buffer, :buffer),
    get(staging, :size),
    :transfer
  )

  ds.hashmap(:vertexbuffer, ds.assoc(buffer, :verticies, length(data)))
end

function indexbuffer(system, config)
  indicies = convert(Vector{UInt16}, get(config, :indicies))
  bytes = sizeof(indicies)

  staging = hw.transferbuffer(system, bytes)

  dev = get(system, :device)
  mem = get(staging, :memory)

  memptr::Ptr{UInt16} = vk.unwrap(vk.map_memory(dev, mem, 0, bytes))
  unsafe_copyto!(memptr, pointer(indicies), length(indicies))
  vk.unmap_memory(dev, mem)

  buffer = hw.buffer(
    system,
    ds.hashmap(
      :size, bytes,
      :usage, vk.BUFFER_USAGE_INDEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT,
      :mode, vk.SHARING_MODE_CONCURRENT,
      :queues, [:graphics, :transfer],
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    )
  )

  hw.copybuffer(
    system,
    get(staging, :buffer), get(buffer, :buffer), get(buffer, :size)
  )

  ds.hashmap(
    :indexbuffer,
    ds.assoc(buffer,
      :verticies, length(indicies),
      :type, vk.INDEX_TYPE_UINT16)
  )
end

function configure(config)
  ds.update(config, :vertex_data, verticies)
end

end # module
