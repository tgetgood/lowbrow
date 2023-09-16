module textures

import FileIO: load
import hardware as hw
import DataStructures as ds
import Vulkan as vk
import commands

# REVIEW: This import automagically allows us to read the bytes out of the
# image. *Do not remove it*!
#
# N.B.: Find a different jpg library. The nested opaque abstractions here are
# shitty to work with.
#
# png and jpg load as transposes of each other. Is that my fault?
import ColorTypes.FixedPointNumbers

function textureimage(system, config)
  dev = get(system, :device)


  image = load(get(config, :texture_file))

  pixels = reduce(*, size(image))

  rgb::Vector{UInt8} = reduce(vcat,
    map(p -> [
        reinterpret(UInt8, p.b), reinterpret(UInt8, p.g), reinterpret(UInt8, p.r),
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

  commands.cmdseq(system, :transfer) do cmd
    commands.transitionimage(cmd, system, ds.hashmap(
      :image, get(vkim, :image),
      :srclayout, vk.IMAGE_LAYOUT_UNDEFINED,
      :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :dstaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :srcstage, vk.PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT
    ))

    commands.copybuffertoimage(
      cmd, system, get(staging, :buffer), get(vkim, :image), size(image)
    )

    commands.transitionimage(cmd, system, ds.hashmap(
      :image, get(vkim, :image),
      :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :srcaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :dstaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
      :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT,
      :srcqueue, ds.getin(system, [:queues, :transfer]),
      :dstqueue, ds.getin(system, [:queues, :graphics])
    ))
  end

  commands.transitionimage(system, ds.hashmap(
    :image, get(vkim, :image),
    :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    :dstlayout, vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    :srcaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
    :dstaccess, vk.ACCESS_SHADER_READ_BIT,
    :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
    :dststage, vk.PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
    :qf, :graphics
  ))

  view = hw.imageview(
      system,
      ds.hashmap(:format, hw.findformat(system, config).format),
      get(vkim, :image),
    )

  return ds.hashmap(
    :texture, vkim,
    :textureimageview, view,
    :sampler, hw.texturesampler(system, config)
  )
end

# TODO: The uniform and texture sampler are confounded here. They need to be
# allocated together, so that should happen around pipeline creation from specs
# created elsewhere.
function allocatesets(system, config)
  dev = get(system, :device)

  layout = vk.unwrap(vk.create_descriptor_set_layout(
    dev,
    [vk.DescriptorSetLayoutBinding(
        0,
        vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        vk.SHADER_STAGE_VERTEX_BIT;
        descriptor_count=1
      ),
      vk.DescriptorSetLayoutBinding(
        1,
        vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        vk.SHADER_STAGE_FRAGMENT_BIT;
        descriptor_count=1
      )]
  ))

  dsets = vk.unwrap(vk.allocate_descriptor_sets(
    dev,
    vk.DescriptorSetAllocateInfo(get(system, :descriptorpool), [layout, layout])
  ))

  sam = get(system, :sampler)
  image = get(system, :textureimageview)

   map(x -> vk.update_descriptor_sets(
    dev,
    [vk.WriteDescriptorSet(
        x[1],
        0,
        0,
        vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER,
        [],
        [vk.DescriptorBufferInfo(0, get(x[2], :size); buffer=get(x[2], :buffer))],
        []
      ),
      vk.WriteDescriptorSet(
        x[1],
        1,
        0,
        vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER,
        [vk.DescriptorImageInfo(
          sam, image, vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
        )],
        [],
        []
      )
    ],
    []
  ),
  zip(dsets, get(system, :uniformbuffers))
  )

  ds.hashmap(
    :dsets, ds.hashmap(
      :descriptorsetlayout, layout,
      :descriptorsets, dsets
    )
  )
end

end
