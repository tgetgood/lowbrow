module commands

import Vulkan as vk

import hardware as hw
import resources: shaderstagebits

import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

function wait_semaphore(
  dev::vk.Device, info::vk.SemaphoreSubmitInfo, timeout=typemax(UInt)
)
  vk.wait_semaphores(
    dev, vk.SemaphoreWaitInfo([info.semaphore], [info.value]), timeout
  )
end

function wait_semaphores(
  dev::vk.Device, infos::Vector{vk.SemaphoreSubmitInfo}, timeout=typemax(UInt)
)
  vk.wait_semaphores(
    dev, vk.SemaphoreWaitInfo(
      ds.into!([], map(x -> x.semaphore), infos),
      ds.into!([], map(x -> x.value), infos)
    ),
    timeout
  )
end

"""
Returns a timeline semaphore which will signal `1` when submitted commands are
finished.

Also starts a new task which waits and collects the command buffer. Some sort of
pool would be a better design, but this suffices for now.
"""
function cmdseq(body, system, qf;
  level=vk.COMMAND_BUFFER_LEVEL_PRIMARY, wait=[])

  signal = hw.timelinesemaphore(system.device, 0)
  post = vk.SemaphoreSubmitInfo(signal, UInt(1), 0)

  pool = hw.getpool(system, qf)
  queue = hw.getqueue(system, qf)

  # FIXME: command pools are not thread safe, so this whole mechanism needs to
  # be rethought.
  cmds = hw.commandbuffers(system, 1, qf, level)
  cmd = cmds[1]

  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  body(cmd)

  vk.end_command_buffer(cmd)

  cbi = vk.CommandBufferSubmitInfo(cmd, 0)

  vk.queue_submit_2(queue, [vk.SubmitInfo2(wait, [cbi], [post])])

  hw.thread() do
    wait_semaphore(get(system, :device), post,)
    vk.free_command_buffers(get(system, :device), pool, cmds)
  end

  return post
end

function recordcomputation(
  cmd, pipeline, layout, workgroup=[1, 1, 1], dsets=[], pcs=ds.emptymap
)
  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  vk.cmd_bind_pipeline(cmd, vk.PIPELINE_BIND_POINT_COMPUTE, pipeline)

  if !ds.emptyp(pcs)
    vk.cmd_push_constants(
      cmd,
      layout,
      vk.SHADER_STAGE_COMPUTE_BIT,
      get(pcs, :offset, 0),
      get(pcs, :size),
      Ptr{Nothing}(pointer(get(pcs, :value)))
    )
  end

  vk.cmd_bind_descriptor_sets(
    cmd,
    vk.PIPELINE_BIND_POINT_COMPUTE,
    layout,
    0,
    dsets,
    []
  )

  vk.cmd_dispatch(cmd, workgroup...)

  vk.end_command_buffer(cmd)
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

function todevicelocal(system, data, buffers...)
  staging = hw.transferbuffer(system, sizeof(data))

  memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
    get(system, :device), get(staging, :memory), 0, sizeof(data)
  ))

  unsafe_copyto!(memptr, pointer(data), length(data))

  vk.unmap_memory(get(system, :device), get(staging, :memory))

  post = cmdseq(system, :transfer) do cmd
    for buffer in buffers
      copybuffer(
        cmd,
        get(staging, :buffer),
        get(buffer, :buffer),
        get(staging, :size),
        :transfer
      )
    end
  end

  # This *seems* to fix a highly intermittent use after free of the staging buffer.
  # I can't replicate the issue reliably enough to call it fixed.
  hw.thread() do
    wait_semaphore(get(system, :device), post)
    staging
  end

  # REVIEW: I'm trying a convention where functions which submit modifications
  # to buffers return SemaphoreSubmitInfos. Then we package those with the buffer and any downstream consumers know for what to wait when submitting further changes.
  post
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

  wait_semaphore(dev, post)

  out = Vector{T}(undef, Int(size / sizeof(T)))

  memptr::Ptr{T} = vk.unwrap(vk.map_memory(
    dev, get(staging, :memory), 0, size
  ))

  unsafe_copyto!(memptr, pointer(out), length(out))

  vk.unmap_memory(dev, get(staging, :memory))

  return out
end

end # module
