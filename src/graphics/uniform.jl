module uniform

import Vulkan as vk

import DataStructures as ds
import hardware as hw

function allocatebuffers(system, config, binding)
  T = get(binding, :eltype)
  n = get(binding, :size)
  frames = get(config, :concurrent_frames, 1)

  ds.into(
    [],
    map(_ -> hw.buffer(system, ds.hashmap(
      :size, n * sizeof(T),
      :usage, vk.BUFFER_USAGE_UNIFORM_BUFFER_BIT,
      :queues, [:graphics],
      :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                    vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
    )))
    ∘
    map(x -> ds.assoc(x,
      :memptr, Ptr{T}(vk.unwrap(vk.map_memory(
        get(system, :device), get(x, :memory), 0, get(x, :size)
      )))
    )),
    1:frames
  )
end

function setubo!(buffer, data)
  unsafe_copyto!(get(buffer, :memptr), pointer([data]), 1)
end

end
