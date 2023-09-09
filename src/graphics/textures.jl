module textures

import FileIO: load
import hardware as hw
import DataStructures as ds
import Vulkan as vk

function textureimage(system, config)
  dev = get(system, :device)

  image = load(*(@__DIR__, "/../../assets/texture.jpg"))

  pixels = reduce(*, size(image))

  rgb::Vector{UInt8} = reduce(vcat,
    map(p -> [
        reinterpret(UInt8, p.r), reinterpret(UInt8, p.g), reinterpret(UInt8, p.b),
        0xff
      ],
      image
    )
  )

  staging = hw.transferbuffer(system, sizeof(rgb))

  memptr::Ptr{UInt8} = vk.unwrap(vk.map_memory(
    dev,
    get(staging, :memory),
    0,
    get(staging, :size)
  ))

  unsafe_copyto!(memptr, pointer(rgb), length(rgb))

  vk.unmap_memory(dev, get(staging, :memory))

  vkim = hw.createimage(system, ds.hashmap(
    :format, vk.FORMAT_B8G8R8A8_SRGB,
    :queues, [:transfer, :graphics],
    :size, size(image),
    :sharingmode, vk.SHARING_MODE_EXCLUSIVE,
    :usage, vk.IMAGE_USAGE_TRANSFER_DST_BIT | vk.IMAGE_USAGE_SAMPLED_BIT,
    :memoryflags, vk.MEMORY_PROPERTY_DEVICE_LOCAL_BIT
  ))

  # TODO: Combine the 4 commands into 1 buffer.

  hw.transitionimage(system, ds.hashmap(
    :image, get(vkim, :image),
    :srclayout, vk.IMAGE_LAYOUT_UNDEFINED,
    :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
  ))

  hw.copybuffertoimage(
    system, get(staging, :buffer), get(vkim, :image), size(image)
  )

  hw.transitionimage(system, ds.hashmap(
    :image, get(vkim, :image),
    :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    :srcqueue, ds.getin(system, [:queues, :transfer]),
    :dstqueue, ds.getin(system, [:queues, :graphics])
  ))

  hw.transitionimage(system, ds.hashmap(
    :image, get(vkim, :image),
    :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    :dstlayout, vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    :qf, :graphics
  ))

  return ds.hashmap(:texture, vkim)
end

function textureimageview(system, config)
  hw.imageview(
    system,
    ds.getin(system, [:texture, :image]),
    hw.findformat(system, config).format
  )
end

function allocatesets(system, config)
  dev = get(system, :device)

  layout = vk.unwrap(vk.create_descriptor_set_layout(
    dev,
    [vk.DescriptorSetLayoutBinding(
      1,
      vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      vk.SHADER_STAGE_FRAGMENT_BIT;
      descriptor_count=1
    )]
  ))

  dsets = vk.unwrap(vk.allocate_descriptor_sets(
    dev,
    vk.DescriptorSetAllocateInfo(get(system, :descriptorpool), [layout])
  ))

  sam = hw.texturesampler(system, config)
  image = textureimageview(system, config)

  writes = [vk.WriteDescriptorSet(
      dsets[1],
      0,
      0,
      vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
      [],
      [vk.DescriptorImageInfo(sam, image, layout)],
      []
    )]

  ds.hashmap(
    :textures, ds.hashmap(
      :descriptorsetlayout, layout,
      :descriptorsets, dsets
      :writes, writes
    )
  )
end

end
