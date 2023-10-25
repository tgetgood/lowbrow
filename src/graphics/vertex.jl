module vertex

import Vulkan as vk

import DataStructures as ds

import hardware as hw
import commands

struct Vertex
  position::NTuple{3, Float32}
  colour::NTuple{3, Float32}
  texuture_coordinates::NTuple{2, Float32}
end

function vert(pos, colour, tex)
  Vertex(tuple(pos...), tuple(colour...), tuple(tex...))
end

function verticies(xs)::Vector{Vertex}
  ds.into([], map(x -> vert(x...)), xs)
end

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

function indexbuffer(system, xs)
  if length(xs) < typemax(UInt16)
    T = UInt16
  else
    T = UInt32
  end

  indicies = convert(Vector{T}, xs)
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

function configure(config)
  ds.update(config, :vertex_data, verticies)
end

end # module
