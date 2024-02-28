# TODO: This should be expanded into a shared utils library. Combine with
# texture and anything else that creates a higher level interface
module vertex

import Vulkan as vk

import DataStructures as ds

import hardware as hw
import Commands

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

  Commands.todevicelocal(system, data, buffer)

  ds.assoc(buffer,
    :verticies, length(data),
    :type, eltype(data)
  )
end

function indexbuffer(system, indicies)
  @info typeof(indicies)
  T = eltype(indicies)

  buffer = hw.buffer(
    system,
    ds.hashmap(
      # indicies might be a persistent vector, I suppose.
      :size, sizeof(T) * length(indicies),
      :usage, [:index_buffer, :transfer_dst],
      :queues, [:graphics, :transfer],
      :memoryflags, :device_local
    )
  )

  Commands.todevicelocal(system, indicies, buffer)

  ds.assoc(buffer,
    :verticies, length(indicies),
    :type, T == UInt16 ? vk.INDEX_TYPE_UINT16 : vk.INDEX_TYPE_UINT32
  )
end

function buffers(system, verticies, indicies=nothing)
  (
    vertexbuffer(system, verticies),
    indicies === nothing ? nothing : indexbuffer(system, indicies)
  )
end

end # module
