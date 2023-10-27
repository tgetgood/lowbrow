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

program = ds.hashmap(
  :name, "Quad",
  :shaders, ds.hashmap(
    :vertex, "quad.vert",
    :fragment, "quad.frag"
  ),
  :verticies, ds.hashmap(
    :data, [
      [[-0.6, -0.6, 0.3], [1, 0, 0]],
      [[0.5, -0.5, 0.3], [0, 1, 0]],
      [[0.3, 0.3, 0.3], [0, 0, 1]],
      [[-0.5, 0.5, 0.3], [1, 1, 1]]
    ],
    :type, Vertex,
    :loader, vert
  ),
  :indicies, ds.hashmap(
    :data, [0, 1, 2, 2, 3, 0,],
    :loader, UInt16
  )
)

function assemblerender(system, config)
  if ds.containsp(config, :indicies)
    ib = indexbuffer(system, map(
      ds.getin(config, [:indicies, :loader]),
      ds.getin(config, [:indicies, :data])
    ))
  else
    ib = ds.emptymap
  end

  merge(
    ds.selectkeys(system, [
      :renderpass,
      :viewports,
      :scissors,
      :pipeline,
      :pipelinelayout,
    ]),
    vertexbuffer(system, map(
      ds.getin(config, [:verticies, :loader]),
      ds.getin(config, [:verticies, :data])
    )),
    ib,
    ds.hashmap(:descriptorsets, [])
 )
end

end # module
