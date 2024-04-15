module Sync

import ..Helpers: thread

import Vulkan as vk
import DataStructures as ds

function timelinesemaphore(dev::vk.Device, init=1)
  vk.unwrap(vk.create_semaphore(
    dev,
    vk.SemaphoreCreateInfo(
      next=vk.SemaphoreTypeCreateInfo(
        vk.SEMAPHORE_TYPE_TIMELINE,
        UInt(init)
      )
    )
  ))
end

function ssi(dev, init=1, df=0)
  vk.SemaphoreSubmitInfo(timelinesemaphore(dev, init), UInt(init + 1), df)
end

function tick(ss::vk.SemaphoreSubmitInfo)
  vk.SemaphoreSubmitInfo(ss.semaphore, ss.value + 1, ss.device_index)
end

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

function freeafter(device, sems, resources...)
  thread() do
    Sync.wait_semaphores(device, sems)
    for r in resources
      finalize(r)
    end
  end
end

end
