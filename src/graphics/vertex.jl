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

# FIXME: These data shouldn't live here.

vertex_data = [
  [[0, -0.5], [1, 1, 1]],
  [[0.5, 0.5], [0, 1, 0]],
  [[-0.5, 0.5], [0, 0, 1]]
]

vattrs = [
  ds.hashmap(
    :fieldname, :position,
    :format, vk.FORMAT_R32G32_SFLOAT,
    :location, 0
  ),
  ds.hashmap(
    :fieldname, :colour,
    :format, vk.FORMAT_R32G32B32_SFLOAT,
    :location, 1
  )
]

function input_state(T, attrs)
  # find field offsets in struct via reflection
  attrds = map(
    (m, i) -> ds.assoc(m, :field, i),
    attrs,
    indexin(fieldnames(T), map(x -> get(x, :fieldname), attrs))
  )

  vk.PipelineVertexInputStateCreateInfo(
    [vk.VertexInputBindingDescription(
      0, sizeof(T), vk.VERTEX_INPUT_RATE_VERTEX
    )],
    map(
      x -> vk.VertexInputAttributeDescription(
        get(x, :location),
        0,
        get(x, :format),
        fieldoffset(Vertex, get(x, :field))
      ),
      attrds
    )
  )
end

function bufferfrom(data)
  function(config, system)
    buffer = hw.buffer(
      ds.assoc(
        config,
        :size, sizeof(data),
        :usage, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT,
        :mode, vk.SHARING_MODE_EXCLUSIVE,
        :queue, :graphics,
        :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                      vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
      ),
      system)

    memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
      get(system, :device), get(buffer, :memory), 0, sizeof(data)
    ))

    unsafe_copyto!(memptr, pointer(data), length(data))

    # I'm guessing unsafe_copyto! just does:
    # ccall(
    #   :memcpy, Cvoid, (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
    #   memptr, pointer(data), sizeof(data)
    # )

    vk.unmap_memory(get(system, :device), get(buffer, :memory))

    ds.hashmap(:vertexbuffer, ds.assoc(buffer, :verticies, length(data)))
  end
end

end # module
