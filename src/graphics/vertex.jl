# TODO: This should be expanded into a shared utils library. Combine with
# texture and anything else that creates a higher level interface
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
      :usage, [:vertex_buffer, :transfer_dst],
      :queues, [:graphics, :transfer],
      :memoryflags, :device_local
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
      :usage, [:index_buffer, :transfer_dst],
      :queues, [:graphics, :transfer],
      :memoryflags, :device_local
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

end # module
