module Commands

import Vulkan as vk

import DataStructures as ds

import hardware as hw
import TaskPipelines as tp

function wait_semaphore(
  dev::vk.Device, info::vk.SemaphoreSubmitInfo, timeout=typemax(UInt)
)
  vk.wait_semaphores(
    dev, vk.SemaphoreWaitInfo([info.semaphore], [info.value]), timeout
  )
end

function todevicelocal(system, data, buffers...)
  dev = system.device
  staging = hw.transferbuffer(system, sizeof(data))

  memptr::Ptr{eltype(data)} = vk.unwrap(vk.map_memory(
    dev, staging.memory, 0, sizeof(data)
  ))

  unsafe_copyto!(memptr, pointer(data), length(data))

  vk.unmap_memory(dev, staging.memory)

  join = tp.record(system.pipelines.host_transfer) do cmd
    for buffer in buffers
      vk.cmd_copy_buffer(
        cmd, staging.buffer, buffer.buffer, [vk.BufferCopy(0, 0, staging.size)]
      )
    end
  end

  hw.thread() do
    (post, _) = take!(join)
    wait_semaphore(system.device, post)
    staging
  end
end

end #module
