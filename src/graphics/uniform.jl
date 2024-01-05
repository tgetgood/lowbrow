module uniform

import Vulkan as vk

import DataStructures as ds
import hardware as hw

function allocatebuffers(system, T, n)
  ds.into(
    [],
    map(_ -> hw.buffer(system, ds.hashmap(
      :size, sizeof(T),
      :usage, :uniform_buffer,
      :queues, [:graphics],
      :memoryflags, [:host_visible, :host_coherent]
    )))
    ∘
    map(x -> ds.assoc(x,
      :memptr, Ptr{T}(vk.unwrap(vk.map_memory(
        get(system, :device), get(x, :memory), 0, get(x, :size)
      ))),
      :size, sizeof(T)
    )),
    1:n
  )
end

function setubo!(buffer, data)
  unsafe_copyto!(get(buffer, :memptr), pointer([data]), 1)
end

end
