module commands

import Vulkan as vk

import Helpers: thread
import Sync

import hardware as hw
import resources: shaderstagebits

import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

function copybuffertoimage(cmd, system, src, dst, size, qf=:transfer)
  vk.cmd_copy_buffer_to_image(
    cmd,
    src,
    dst,
    vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    [vk.BufferImageCopy(
      0, 0, 0,
      vk.ImageSubresourceLayers(vk.IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
      vk.Offset3D(0, 0, 0),
      vk.Extent3D(size..., 1)
    )]
  )
end

function mipblit(cmd, config)
  (x, y) = get(config, :size)

  b = vk.ImageBlit(
    vk.ImageSubresourceLayers(
      vk.IMAGE_ASPECT_COLOR_BIT,
      get(config, :level),
      0, 1
    ),
    (vk.Offset3D(0, 0, 0), vk.Offset3D(x, y, 1)),
    vk.ImageSubresourceLayers(
      vk.IMAGE_ASPECT_COLOR_BIT,
      get(config, :level) + 1,
      0, 1
    ),
    (vk.Offset3D(0, 0, 0), vk.Offset3D(div(x, 2), div(y, 2), 1))
  )

  vk.cmd_blit_image(
    cmd,
    getin(config, [:image, :image]),
    vk.IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
    getin(config, [:image, :image]),
    vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    [b],
    vk.FILTER_LINEAR
  )
end

# FIXME: Should be (cmd, image, newstate)
# where `image` is a map that holds the current state of the image.
function transitionimage(cmd::vk.CommandBuffer, config)
  aspect = get(config, :aspect, vk.IMAGE_ASPECT_COLOR_BIT)

  barrier = vk.unwrap(vk.ImageMemoryBarrier(
    get(config, :srcaccess, vk.AccessFlag(0)),
    get(config, :dstaccess, vk.AccessFlag(0)),
    get(config, :srclayout),
    get(config, :dstlayout),
    get(config, :srcqueue, vk.QUEUE_FAMILY_IGNORED),
    get(config, :dstqueue, vk.QUEUE_FAMILY_IGNORED),
    ds.getin(config, [:image, :image]),
    vk.ImageSubresourceRange(
      aspect,
      ds.get(config, :basemiplevel, 0),
      ds.get(config, :miplevels, 1),
      0, 1
    )))

  vk.cmd_pipeline_barrier(
    cmd, [], [], [barrier];
    src_stage_mask=get(config, :srcstage, vk.PipelineStageFlag(0)),
    dst_stage_mask=get(config, :dststage, vk.PipelineStageFlag(0))
  )
end

function transitionimage(system::ds.Map, config)
  cmdseq(system, get(config, :qf)) do cmd
    transitionimage(cmd, config)
  end
end

function copybuffer(system::ds.Map, src, dst, size, queuefamily=:transfer)
  commands.cmdseq(system, queuefamily) do cmd
    copybuffer(cmd, src, dst, size, queuefamily)
  end
end

function copybuffer(cmd::vk.CommandBuffer, src, dst, size,
  queuefamily=:transfer
)
  vk.cmd_copy_buffer(cmd, src, dst, [vk.BufferCopy(0, 0, size)])
end

"""
Copy outputs of compute shaders back to cpu ram. Returns Vector<T>.
"""
function fromdevicelocal(system, T, buffer)
  size = get(buffer, :size)
  dev = get(system, :device)

  staging = hw.transferbuffer(system, size)

  post = cmdseq(system, :transfer) do cmd
    copybuffer(
      cmd,
      get(buffer, :buffer),
      get(staging, :buffer),
      get(staging, :size),
      :transfer
    )
  end

  Sync.wait_semaphore(dev, post)

  out = Vector{T}(undef, Int(size / sizeof(T)))

  memptr::Ptr{T} = vk.unwrap(vk.map_memory(
    dev, get(staging, :memory), 0, size
  ))

  unsafe_copyto!(memptr, pointer(out), length(out))

  vk.unmap_memory(dev, get(staging, :memory))

  return out
end

end # module
