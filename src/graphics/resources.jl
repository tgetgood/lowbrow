"""
Helper functions to create Vulkan info structs.

Not the place to create live Vulkan objects.
"""
module resources

import Vulkan as vk
import DataStructures as ds
import DataStructures: into, hashmap

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
        get(m, :usage),
        get(m, :stage);
        descriptor_count=get(m, :descriptor_count, 1)
      )),
      bindings
    )
  )
end

"""
Returns a DescriptorPoolCreateInfo appropriate to the given layout and config.
"""
function descriptorpool(layout, frames)
  vk.DescriptorPoolCreateInfo(
    frames * length(layout.bindings),
    into([], map(x -> vk.DescriptorPoolSize(
        x.descriptor_type,
        x.descriptor_count * frames
      )),
      layout.bindings
    )
  )
end

function descriptorsetallocate(layout, frames)
  v
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

end
