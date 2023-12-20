module commands

import Vulkan as vk

import hardware as hw

import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

"""
Returns a timeline semaphore which will signal `1` when submitted commands are
finished.

Also starts a new task which waits and collects the command buffer. Some sort of
pool would be a better design, but this suffices for now.
"""
function cmdseq(body, system, qf;
                level=vk.COMMAND_BUFFER_LEVEL_PRIMARY, wait=[])

  signal = vk.unwrap(vk.create_semaphore(
    get(system, :device),
    vk.SemaphoreCreateInfo(
      next=vk.SemaphoreTypeCreateInfo(
        vk.SEMAPHORE_TYPE_TIMELINE,
        0
      )
    )
  ))

  pool = hw.getpool(system, qf)
  queue = hw.getqueue(system, qf)

  cmds = hw.commandbuffers(system, 1, qf, level)
  cmd = cmds[1]

  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  body(cmd)

  vk.end_command_buffer(cmd)

  vk.queue_submit(queue, [vk.SubmitInfo(wait,[],[cmd], [signal];
    next=vk.TimelineSemaphoreSubmitInfo(signal_semaphore_values=[UInt(1)])
  )])

  @async begin
    vk.wait_semaphores(
      get(system, :device),
      vk.SemaphoreWaitInfo([signal], [UInt(1)]),
      typemax(UInt)
    )
    vk.free_command_buffers(get(system, :device), pool, cmds)
  end

  return signal
end

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
  gd(x, k) = get(x, k, [0,1])

  function gd(k)
    x = get(config, k)
    return (
      [gd(x, :x)[1], gd(x, :y)[1], gd(x, :z)[1]],
      [gd(x, :x)[2], gd(x, :y)[2], gd(x, :z)[2]]
    )
  end

  (x, y) = get(config, :size)

  b = vk.ImageBlit(
    vk.ImageSubresourceLayers(
      vk.IMAGE_ASPECT_COLOR_BIT,
      get(config, :level),
      0, 1
    ),
    (vk.Offset3D(0,0,0), vk.Offset3D(x, y, 1)),
    vk.ImageSubresourceLayers(
      vk.IMAGE_ASPECT_COLOR_BIT,
      get(config, :level) + 1,
      0, 1
    ),
    (vk.Offset3D(0,0,0), vk.Offset3D(div(x, 2), div(y, 2), 1))
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
    copybuffer(cmd, system, src, dst, size, queuefamily)
  end
end

function copybuffer(cmd::vk.CommandBuffer, system, src, dst, size,
                    queuefamily=:transfer)
    vk.cmd_copy_buffer(cmd, src, dst, [vk.BufferCopy(0,0,size)])
end

function todevicelocal(system, data, buffers...)
  staging = hw.transferbuffer(system, sizeof(data))

  memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
    get(system, :device), get(staging, :memory), 0, sizeof(data)
  ))

  unsafe_copyto!(memptr, pointer(data), length(data))

  vk.unmap_memory(get(system, :device), get(staging, :memory))

  cmdseq(system, :transfer) do cmd
    for buffer in buffers
      copybuffer(
        cmd,
        system,
        get(staging, :buffer),
        get(buffer, :buffer),
        get(staging, :size),
        :transfer
      )
    end
  end

  # TODO: Test if this solves the use after free on dedicated hardware.
  # Can't replicate on laptop (embedded gpu).

  @async begin
    vk.wait_semaphores(
      get(system, :device),
      vk.SemaphoreWaitInfo([sem], [UInt(1)]),
      typemax(UInt)
    )

    staging
  end

end

end # module
