module commands

import Vulkan as vk
import DataStructures: getin, emptymap, hashmap, emptyvector, into

function pool(config, system)
  hashmap(
    :pool,
    vk.unwrap(vk.create_command_pool(
      get(system, :device),
      getin(system, [:queues, :graphics]);
      flags=vk.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
    ))
  )
end

function buffer(config, system)
  hashmap(
    :commandbuffrt,
    vk.unwrap(vk.allocate_command_buffers(
      get(system, :device),
      vk.CommandBufferAllocateInfo(
        get(system, :pool),
        vk.COMMAND_BUFFER_LEVEL_PRIMARY,
        1
      )
    ))
  )
end

end
