"""
Helper functions to create Vulkan info structs.

Not the place to create live Vulkan objects.
"""
module resources

import Vulkan as vk
import DataStructures as ds
import DataStructures: into, hashmap

##### Enumerations

const bufferusagebits = hashmap(
  :vertex_buffer, vk.BUFFER_USAGE_VERTEX_BUFFER_BIT,
  :index_buffer, vk.BUFFER_USAGE_INDEX_BUFFER_BIT,
  :storage_buffer, vk.BUFFER_USAGE_STORAGE_BUFFER_BIT,
  :uniform_buffer, vk.BUFFER_USAGE_UNIFORM_BUFFER_BIT,
  :transfer_dst, vk.BUFFER_USAGE_TRANSFER_DST_BIT,
  :transfer_src, vk.BUFFER_USAGE_TRANSFER_SRC_BIT
)

const memorypropertybits = hashmap(
  :device_local, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT,
  :host_coherent, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT,
  :host_visible, vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
)

const sharingmodes = hashmap(
  :exclusive, vk.SHARING_MODE_EXCLUSIVE,
  :concurrent, vk.SHARING_MODE_CONCURRENT
)

const imageusagebits = hashmap(
  :colour_attachment, vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  :depth_stencil_attachment, vk.IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
  :input_attachment, vk.IMAGE_USAGE_INPUT_ATTACHMENT_BIT,
  :sampled, vk.IMAGE_USAGE_SAMPLED_BIT,
  :storage, vk.IMAGE_USAGE_STORAGE_BIT,
  :transfer_dst, vk.IMAGE_USAGE_TRANSFER_DST_BIT,
  :transfer_src, vk.IMAGE_USAGE_TRANSFER_SRC_BIT,
  :transient_attachment, vk.IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT
)

const imagelayouts = hashmap()

const accessbits = hashmap()

const pipelinestagebits = hashmap()

const shaderstagebits = hashmap(
  :vertex, vk.SHADER_STAGE_VERTEX_BIT,
  :fragment, vk.SHADER_STAGE_FRAGMENT_BIT,
  :compute, vk.SHADER_STAGE_COMPUTE_BIT,
  :geometry, vk.SHADER_STAGE_GEOMETRY_BIT,
  :tessellationcontrol, vk.SHADER_STAGE_TESSELLATION_CONTROL_BIT,
  :tessellationeval, vk.SHADER_STAGE_TESSELLATION_EVALUATION_BIT
)

const descriptortypes = hashmap(
  :uniform, vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
  :sampler, vk.DESCRIPTOR_TYPE_SAMPLER,
  :sampled_image, vk.DESCRIPTOR_TYPE_SAMPLED_IMAGE,
  :combined_sampler, vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
  :ssbo, vk.DESCRIPTOR_TYPE_STORAGE_BUFFER,
  :image, vk.DESCRIPTOR_TYPE_STORAGE_IMAGE
)

##### Resource Creation

"""
Returns Vector{DescriptorSetLayoutBinding} for data of `types` at `stages`.

Three different aspects of the render have to come together for descriptors: the
actual data blobs, the use to which each blob will be put, and the stages at
which it will be used.

The last two are essentially static in a given pipeline and can be computed
ahead of time.
"""
function descriptorsetlayout(bindings)
  vk.DescriptorSetLayoutCreateInfo(
    ds.into(
      [],
      ds.mapindexed((i, m) -> vk.DescriptorSetLayoutBinding(
        i - 1,
        get(descriptortypes, get(m, :type)),
        get(shaderstagebits, get(m, :stage));
        descriptor_count=get(m, :descriptor_count, 1)
      )),
      bindings
    )
  )
end

"""
Returns a DescriptorPoolCreateInfo appropriate to the given layout and config.
"""
function descriptorpool(layout, size)
  vk.DescriptorPoolCreateInfo(
    size * length(layout.bindings),
    into([], map(x -> vk.DescriptorPoolSize(
        x.descriptor_type,
        x.descriptor_count * size
      )),
      layout.bindings
    )
  )
end

rasterizationstatedefaults = ds.hashmap(
)

function rasterizationstate(config)
  config = merge(rasterizationstatedefaults, config)

  vk.PipelineRasterizationStateCreateInfo(
    false,
    false,
    vk.POLYGON_MODE_FILL,
    vk.FRONT_FACE_CLOCKWISE,
    false,
    0.0, 0.0, 0.0,
    1.0;
    cull_mode=vk.CULL_MODE_BACK_BIT
  )
end

##### Graphics Pipeline

function channels(n, w)
  ds.reduce(*, "", ds.take(n, map(s -> s*w, ["R", "G", "B", "A"])))
end

const typenames = hashmap(
  Signed, "SINT",
  Unsigned, "UINT",
  AbstractFloat, "SFLOAT"
)

"""
Returns the Vulkan Format for julia type `T`.

`T` must have fixed size.

Not tested for completeness.
"""
function typeformat(T)
  n = Int(sizeof(T) / sizeof(eltype(T)))
  w = string(sizeof(eltype(T)) * 8)
  t = get(typenames, supertype(eltype(T)))

  getfield(vk, Symbol("FORMAT_" * channels(n, w) * "_" * t))
end

"""
Generates PiplineVertexInputStateCreateInfo from struct `T` via reflection.

N.B.: The location pragmata in the shaders are assumed to follow the order in
`fields` which defaults to the fieldnames in order as defined in `T`.
"""
function vertex_input_state(T, fields)
  fnames = fieldnames(T)

  vk.PipelineVertexInputStateCreateInfo(
    [vk.VertexInputBindingDescription(
      0, sizeof(T), vk.VERTEX_INPUT_RATE_VERTEX
    )],
    ds.into(
      [],
      ds.mapindexed((i, j) -> vk.VertexInputAttributeDescription(
        i - 1,
        0,
        typeformat(fieldtype(T, fnames[j])),
        fieldoffset(T, j)
      )
      ),
      indexin(ds.into([], fields), ds.into([], fnames))
    )
  )
end

function vertex_input_state(T)
  vertex_input_state(T, fieldnames(T))
end

end
