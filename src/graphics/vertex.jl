module vertex

import Vulkan as vk

import DataStructures as ds

import hardware as hw
import commands

# TODO: These buffers should both use SHARING_MODE_EXCLUSIVE and be returned
# after transfer to the graphics queue.

function vertexbuffer(system, data)
  buffer = hw.buffer(
    system,
    ds.hashmap(
      :size, sizeof(data),
      :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT,
      :queues, [:graphics, :transfer],
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    )
  )

  commands.todevicelocal(system, data, buffer)

  ds.hashmap(:vertexbuffer, ds.assoc(buffer,
    :verticies, length(data),
    :type, eltype(data)
  ))
end

function indexbuffer(system, indicies)
  T = eltype(indicies)
  bytes = sizeof(indicies)

  staging = hw.transferbuffer(system, bytes)

  dev = get(system, :device)
  mem = get(staging, :memory)

  memptr::Ptr{T} = vk.unwrap(vk.map_memory(dev, mem, 0, bytes))
  unsafe_copyto!(memptr, pointer(indicies), length(indicies))
  vk.unmap_memory(dev, mem)

  buffer = hw.buffer(
    system,
    ds.hashmap(
      :size, bytes,
      :usage, vk.BUFFER_USAGE_INDEX_BUFFER_BIT |
              vk.BUFFER_USAGE_TRANSFER_DST_BIT,
      :queues, [:graphics, :transfer],
      :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
    )
  )

  commands.copybuffer(
    system,
    get(staging, :buffer), get(buffer, :buffer), bytes
  )

  ds.hashmap(
    :indexbuffer,
    ds.assoc(buffer,
      :verticies, length(indicies),
      :type, T == UInt16 ? vk.INDEX_TYPE_UINT16 : vk.INDEX_TYPE_UINT32)
  )
end

##### Simple quad example.

struct Vertex
  position::NTuple{3, Float32}
  colour::NTuple{3, Float32}
end

function vert((pos, colour))
  Vertex(tuple(pos...), tuple(colour...))
end

function load(config)
  config = ds.update(config, :verticies, x -> map(vert, x))
  ds.update(config, :indicies, x -> map(UInt16, x))
end

program = ds.hashmap(
  :name, "Quad",
  :shaders, ds.hashmap(
    :vertex, "quad.vert",
    :fragment, "quad.frag"
  ),
  :model, ds.hashmap(
    :loader, load,
    :vertex_type, Vertex
  ),
  :verticies, [
    [[-0.6, -0.6, 0.3], [1, 0, 0]],
    [[0.5, -0.5, 0.3], [0, 1, 0]],
    [[0.3, 0.3, 0.3], [0, 0, 1]],
    [[-0.5, 0.5, 0.3], [0.5, 0.5, 0.5]]
  ],
  :indicies, [0, 3, 2, 2, 1, 0,]
)

end # module
