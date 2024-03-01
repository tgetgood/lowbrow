"""
Helper functions to create Vulkan info structs.

Not the place to create live Vulkan objects.
"""
module resources

import Vulkan as vk
import DataStructures as ds
import DataStructures: into, hashmap

##### Enumerations

const debugutilsseveritybits = hashmap(
  :verbose, vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
  :info, vk.DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
  :warning, vk.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
  :error, vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
)

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
  :host_visible, vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT,
  :lazy, vk.MEMORY_PROPERTY_LAZILY_ALLOCATED_BIT
)

const sharingmodes = hashmap(
  :exclusive, vk.SHARING_MODE_EXCLUSIVE,
  :concurrent, vk.SHARING_MODE_CONCURRENT
)

const imageusagebits = hashmap(
  :colour, vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
  :depth_stencil, vk.IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
  :input, vk.IMAGE_USAGE_INPUT_ATTACHMENT_BIT,
  :sampled, vk.IMAGE_USAGE_SAMPLED_BIT,
  :storage, vk.IMAGE_USAGE_STORAGE_BIT,
  :transfer_dst, vk.IMAGE_USAGE_TRANSFER_DST_BIT,
  :transfer_src, vk.IMAGE_USAGE_TRANSFER_SRC_BIT,
  :transient, vk.IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT
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

const queuebits = hashmap(
  :graphics, vk.QUEUE_GRAPHICS_BIT,
  :compute, vk.QUEUE_COMPUTE_BIT,
  :transfer, vk.QUEUE_TRANSFER_BIT,
  :sparse_binding, vk.QUEUE_SPARSE_BINDING_BIT,
  :protected, vk.QUEUE_PROTECTED_BIT,
  :video_encode, vk.QUEUE_VIDEO_ENCODE_BIT_KHR,
  :video_decode, vk.QUEUE_VIDEO_DECODE_BIT_KHR
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
        x.descriptor_count
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

##### Bitmask helpers

# How do we catch typographical errors in a dynamic language?

struct Typo end
typo = Typo()

function orlist(bitmap, x::Symbol)
  get(bitmap, x, typo)
end

# OR is such a basic monoid, but because |() needs to return a *typed* zero, we
# can't treat it as such. If you're going to insist on a type system of this
# sort, the identity should be its own type.
#
# I've run into the same problem with datastructures. Making the empty list,
# empty map, empty set, &c. into singleton types is the only way I've figured
# out how to make generic sequence operations play nice with type inference.
bitor() = 0
bitor(x) = x
bitor(x, y) = x | y

function orlist(bitmap, xs)
  flags = ds.transduce(map(k -> get(bitmap, k, typo)), bitor, xs)
  @assert flags !== 0
  flags
end

end
