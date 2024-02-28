module textures

import FileIO as fio
import hardware as hw
import DataStructures as ds
import Vulkan as vk
import Commands
import TaskPipelines as tp
import Sync

# N.B: This import automagically allows us to read the bytes out of the
# image. *Do not remove it*!
#
# TODO: Find a different jpg library. The nested opaque abstractions here are
# shitty to work with.
#
# png and jpg load as transposes of each other. Is that my fault?
import ColorTypes.FixedPointNumbers

function texturesampler(system, config)
  vk.unwrap(vk.create_sampler(
    get(system, :device),
    vk.FILTER_LINEAR,
    vk.FILTER_LINEAR,
    vk.SAMPLER_MIPMAP_MODE_LINEAR,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    vk.SAMPLER_ADDRESS_MODE_REPEAT,
    0,
    true,
    system.spec.device.properties.limits.max_sampler_anisotropy,
    false,
    vk.COMPARE_OP_ALWAYS,
    0,
    get(config, :miplevels, 1),
    vk.BORDER_COLOR_INT_OPAQUE_BLACK,
    false
  ))
end

function bgr(p)
  ds.vector(
    reinterpret(UInt8, p.b), reinterpret(UInt8, p.g), reinterpret(UInt8, p.r)
  )
end

function generatemipmaps(system, vkim)
  props = vk.get_physical_device_format_properties(system.pdev, vkim.format)

  if (props.optimal_tiling_features &
      vk.FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT).val == 0
    @warn "Linear blit not supported, mipmaps won't be generated!"
    return
  end

  mips = get(vkim, :miplevels)

  barrier = ds.hashmap(
    :image, vkim,
    :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    :srcaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
    :dstaccess, vk.ACCESS_TRANSFER_READ_BIT,
    :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
    :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT,
    :qf, :graphics
  )

  postbarrier = ds.hashmap(
    :srclayout, vk.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    :dstlayout, vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
    :srcaccess, vk.ACCESS_TRANSFER_READ_BIT,
    :dstaccess, vk.ACCESS_SHADER_READ_BIT,
    :dststage, vk.PIPELINE_STAGE_FRAGMENT_SHADER_BIT,
  )

  mipconstruct = ds.into(
    ds.emptyvector,
    map(i -> ds.hashmap(
      :prebarrier, ds.assoc(barrier, :basemiplevel, i),
      :blit, ds.hashmap(
        :image, vkim,
        :level, i,
        :size, map(x -> div(x, (2^i)), get(vkim, :resolution))
      ),
    )) ∘
    map(x -> ds.assoc(
      x, :postbarrier, merge(get(x, :prebarrier), postbarrier)
    )),
    0:mips-2 # mip levels start at zero
  )

  tp.sendcmd(system, :render) do cmd
    ds.reduce(0, mipconstruct) do _, x
      Commands.transitionimage(cmd, get(x, :prebarrier))
      Commands.mipblit(cmd, get(x, :blit))
      Commands.transitionimage(cmd, get(x, :postbarrier))
    end

    Commands.transitionimage(
      cmd,
      ds.merge(
        barrier,
        ds.selectkeys(postbarrier, [:dstlayout, :dstaccess, :dststage]),
        ds.hashmap(:basemiplevel, mips-1))
    )
  end
end

function textureimage(system, filename)
  dev = get(system, :device)

  image = fio.load(filename)

  pixels = reduce(*, size(image))

  mips = Int(1 + floor(log2(min(size(image)...))))

  rgb = ds.into!(
    UInt8[],
    map(bgr)
    ∘
    ds.inject(ds.repeat(ds.vector(0xff)))
    ∘
    ds.interleave()
    ∘
    ds.cat(),
    image
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
    :miplevels, mips,
    :sharingmode, :exclusive,
    :usage, [:transfer_src, :transfer_dst, :sampled],
    :memoryflags, :device_local
  ))

  join = tp.record(system.pipelines.host_transfer) do cmd
    Commands.transitionimage(cmd, ds.hashmap(
      :image, vkim,
      :miplevels, mips,
      :srclayout, vk.IMAGE_LAYOUT_UNDEFINED,
      :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :dstaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :srcstage, vk.PIPELINE_STAGE_TOP_OF_PIPE_BIT,
      :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT
    ))

    Commands.copybuffertoimage(
      cmd, system, get(staging, :buffer), get(vkim, :image), size(image)
    )

    Commands.transitionimage(cmd, ds.hashmap(
      :image, vkim,
      :srclayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :dstlayout, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      :srcaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :dstaccess, vk.ACCESS_TRANSFER_WRITE_BIT,
      :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
      :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT,
      :srcqueue, system.spec.queues.queue_families.transfer,
      :dstqueue, system.spec.queues.queue_families.graphics,
    ))

  end

  (post, _) = take!(join)
  Sync.wait_semaphore(system.device, post)

  generatemipmaps(system, vkim)

  view = hw.imageview(
    system,
    # FIXME: Format should not be hardcoded, and should be stored in the image
    # map since it's a property of the image.
    ds.hashmap(:format, vk.FORMAT_B8G8R8A8_SRGB),
    vkim,
  )

  return ds.hashmap(
    :texture, vkim,
    :textureimageview, view,
    :sampler, texturesampler(system, ds.hashmap(:miplevels, mips))
  )
end

end #module
