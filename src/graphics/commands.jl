module commands

import Vulkan as vk

import hardware as hw

import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

function cmdseq(body, system, qf, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  pool = hw.getpool(system, qf)
  queue = hw.getqueue(system, qf)

  cmds = hw.commandbuffers(system, 1, qf, level)
  cmd = cmds[1]

  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  body(cmd)

  vk.end_command_buffer(cmd)

  vk.queue_submit(queue, [vk.SubmitInfo([],[],[cmd],[])])

  vk.queue_wait_idle(queue)

  vk.free_command_buffers(get(system, :device), pool, cmds)
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

function transitionimage(cmd, system::ds.Map, config)
  aspect = get(config, :aspect, vk.IMAGE_ASPECT_COLOR_BIT)

  barrier = vk.unwrap(vk.ImageMemoryBarrier(
    get(config, :srcaccess, vk.AccessFlag(0)),
    get(config, :dstaccess, vk.AccessFlag(0)),
    get(config, :srclayout),
    get(config, :dstlayout),
    get(config, :srcqueue, vk.QUEUE_FAMILY_IGNORED),
    get(config, :dstqueue, vk.QUEUE_FAMILY_IGNORED),
    ds.getin(config, [:image, :image]),
    vk.ImageSubresourceRange(aspect, 0, ds.getin(config, [:image, :mips], 1), 0, 1)))

  vk.cmd_pipeline_barrier(
    cmd, [], [], [barrier];
    src_stage_mask=get(config, :srcstage, vk.PipelineStageFlag(0)),
    dst_stage_mask=get(config, :dststage, vk.PipelineStageFlag(0))
  )
end

function transitionimage(system::ds.Map, config)
  cmdseq(system, get(config, :qf)) do cmd
    transitionimage(cmd, system, config)
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

end
