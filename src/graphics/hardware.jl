module hardware

import window
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, assoc, hashmap, into, emptyvector, emptymap

function containsall(needles, hay)::Bool
  return [nothing] == indexin([nothing], indexin(needles, hay))
end

function instance(_, config)
  ic = get(config, :instance)
  validationlayers = get(ic, :validation)
  extensions = get(ic, :extensions)

  @assert containsall(
    extensions,
    map(
      x -> x.extension_name,
      vk.unwrap(vk.enumerate_instance_extension_properties())
    )
  ) "unsupported extensions required."

  @assert containsall(
    validationlayers,
    map(
      x -> x.layer_name,
      vk.unwrap(vk.enumerate_instance_layer_properties())
    )
  ) "unsupported validation layers required."

  appinfo = vk.ApplicationInfo(
    v"0.0.0",
    v"0.0.0",
    v"1.3";
    application_name="brow",
    engine_name="integrated"
  )

  inst = vk.unwrap(vk.create_instance(
    validationlayers,
    extensions;
    next=ds.containsp(config, :debuginfo) ? get(config, :debuginfo) : C_NULL,
    application_info=appinfo
  ))

  return hashmap(:instance, inst)
end

function findgraphicsqueue(device)
  try
    vk.find_queue_family(device, vk.QUEUE_GRAPHICS_BIT)
  catch e
    return nothing
  end
end

function findpresentationqueue(system, device)
  first(
    filter(
      i -> vk.unwrap(vk.get_physical_device_surface_support_khr(
        device,
        i,
        get(system, :surface)
      )),
      0:length(vk.get_physical_device_queue_family_properties(device))-1
    )
  )
end

function findtransferqueue(device)
  families = ds.mapindexed(
    (x, i) -> (x, i - 1),
    vk.get_physical_device_queue_family_properties(device)
  )

  dedicated = filter(
    x -> (x[1].queue_flags & vk.QUEUE_TRANSFER_BIT) > 0 &&
    (x[1].queue_flags & (vk.QUEUE_GRAPHICS_BIT | vk.QUEUE_COMPUTE_BIT)).val == 0,
    families
  )

  if length(dedicated) > 0
    return first(dedicated)[2]
  else

    nongraphics = filter(
      x -> (x[1].queue_flags & vk.QUEUE_TRANSFER_BIT) > 0 &&
        (x[1].queue_flags & vk.QUEUE_GRAPHICS_BIT).val == 0,
      families
    )

    if length(nongraphics) > 0
      return first(nongraphics)[2]
    else
      return findgraphicsqueue(device)
    end
  end
end


function swapchainsupport(system)
  dev = get(system, :physicaldevice)
  surface = get(system, :surface)

  # capabilities = vk.get_physical_device_surface_capabilities_khr(dev, surface)
  formats = vk.unwrap(vk.get_physical_device_surface_formats_khr(dev; surface))
  modes = vk.unwrap(
    vk.get_physical_device_surface_present_modes_khr(dev; surface)
  )

  return length(formats) > 0 && length(modes) > 0
end


function checkdevice(system, config)
  pdev = get(system, :physicaldevice)
  features = vk.get_physical_device_features(pdev)

  return getin(system, [:queues, :graphics]) !== nothing &&
         getin(system, [:queues, :presentation]) !== nothing &&
         getin(system, [:queues, :transfer]) !== nothing &&
         all(
           map(x -> getproperty(features, x),
             ds.getin(config, [:device, :features]))
         ) &&
         swapchainsupport(system) &&
         containsall(
           getin(config, [:device, :extensions]),
           map(
             x -> x.extension_name,
             vk.unwrap(vk.enumerate_device_extension_properties(pdev))
           )
         ) &&
         containsall(
           getin(config, [:device, :validation]),
           map(
             x -> x.layer_name,
             vk.unwrap(vk.enumerate_device_layer_properties(pdev))
           )
         )
end

function findformat(system, config)
  formats = vk.unwrap(vk.get_physical_device_surface_formats_khr(
    get(system, :physicaldevice);
    surface=get(system, :surface)
  ))

  filtered = filter(
    x -> x.format == getin(config, [:swapchain, :format]) &&
      x.color_space == getin(config, [:swapchain, :colourspace]),
    formats
  )

  if length(filtered) == 0
    nothing
  else
    first(filtered)
  end
end

function findextent(system, config)
  sc = vk.unwrap(vk.get_physical_device_surface_capabilities_khr(
    get(system, :physicaldevice),
    get(system, :surface)
  ))

  win = window.size(get(system, :window))

  vk.Extent2D(
    clamp(win.width, sc.min_image_extent.width, sc.max_image_extent.width),
    clamp(win.height, sc.min_image_extent.height, sc.max_image_extent.height)
  )
end

function findpresentmode(system, config)
  modes = vk.unwrap(
    vk.get_physical_device_surface_present_modes_khr(
      get(system, :physicaldevice);
      surface=get(system, :surface)
    )
  )
  if length(modes) == 0
    nothing
  else
    first(modes)
  end
end

function findqueues(system, device)
  hashmap(
    :graphics, findgraphicsqueue(device),
    :presentation, findpresentationqueue(system, device),
    :transfer, findtransferqueue(device)
  )
end

function pdevice(system, config)
  potential = into(
    emptyvector,
    map(x -> merge(system, hashmap(
      :physicaldevice, x,
      :queues, findqueues(system, x)
    )))
    ∘ filter(system -> checkdevice(system, config)),
    vk.unwrap(vk.enumerate_physical_devices(get(system, :instance)))
  )

  if ds.emptyp(potential)
    nothing
  else
    first(potential)
  end
end

function getqueue(system, queue, index=0)
  vk.get_device_queue(
    get(system, :device),
    getin(system, [:queues, queue]),
    index
  )
end

function createdevice(system, config)
  system = pdevice(system, config)
  queues = get(system, :queues)
  pdev = get(system, :physicaldevice)

  qs2c = ds.vals(
    into(emptymap, map(x -> ds.MapEntry(x, x)), ds.vals(queues))
  )
  qcis::Base.Vector = map(x -> vk.DeviceQueueCreateInfo(x, [1.0]), qs2c)

  dci = vk.DeviceCreateInfo(
    qcis,
    getin(config, [:device, :validation], []),
    getin(config, [:device, :extensions], []);
    enabled_features=
    vk.PhysicalDeviceFeatures(ds.getin(config, [:device, :features])...)
  )

  assoc(system, :device, vk.unwrap(vk.create_device(pdev, dci)))
end

function createswapchain(system, config)
  format = findformat(system, config)
  extent = findextent(system, config)

  sc = vk.create_swapchain_khr(
    get(system, :device),
    get(system, :surface),
    getin(config, [:swapchain, :images]),
    format.format,
    format.color_space,
    extent,
    1, # image arrays
    vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    vk.SHARING_MODE_EXCLUSIVE, # <- FIXME: don't hardcode this
    [],
    vk.SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
    vk.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    findpresentmode(system, config),
    true;
    old_swapchain=get(system, :swapchain, C_NULL)
  )

  hashmap(:swapchain, vk.unwrap(sc), :extent, extent, :format, format)
end

function imageview(system, image, format)
  vk.unwrap(vk.create_image_view(
    get(system, :device),
    image,
    vk.IMAGE_VIEW_TYPE_2D,
    format,
    vk.ComponentMapping(
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY
    ),
    vk.ImageSubresourceRange(
      vk.IMAGE_ASPECT_COLOR_BIT,
      0,
      1,
      0,
      1
    )
  ))
end

function createimageviews(system, config)
  dev = get(system, :device)

  hashmap(
    :imageviews,
    into(
      emptyvector,
      map(image -> imageview(system, image, findformat(system, config).format)),
      vk.unwrap(vk.get_swapchain_images_khr(dev, get(system, :swapchain)))
    )
  )
end

function createcommandpools(system, config)
  dev = get(system, :device)
  qfs = collect(Set(ds.vals(get(system, :queues))))

  hashmap(
    :commandpools,
    ds.zipmap(qfs, map(qf ->
        vk.unwrap(vk.create_command_pool(
          dev,
          qf,
          flags=vk.COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT
        )),
      qfs
    ))
  )
end

function createdescriptorpools(system, config)
  n = get(config, :concurrent_frames)

  hashmap(
    :descriptorpool,
    vk.unwrap(vk.create_descriptor_pool(
      get(system, :device),
      2*n,
      [
        vk.DescriptorPoolSize(vk.DESCRIPTOR_TYPE_UNIFORM_BUFFER, n),
        vk.DescriptorPoolSize(vk.DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, n)
      ]
    ))
  )
end

"""
Returns command pool to use for given queue family `qf`.
"""
function getpool(system, qf)
  getin(system, [:commandpools, getin(system, [:queues, qf])])
end

function findmemtype(system, config)
  properties = vk.get_physical_device_memory_properties(
    get(system, :physicaldevice)
  )

  mask = get(config, :typemask)
  flags = get(config, :flags)

  mt = into(
    [],
    ds.mapindexed((x, i) -> (x, i-1))
    ∘ filter(x -> (mask & (1 << x[2])) > 0)
    ∘ filter(x -> (x[1].property_flags & flags) == flags)
    ,
    properties.memory_types[1:properties.memory_type_count]
  )

  @assert length(mt) > 0

  mt[1]
end

function buffer(system, config)
  dev = get(system, :device)

  bci = vk.BufferCreateInfo(
    get(config, :size),
    get(config, :usage),
    get(config, :mode),
    into([], map(x -> getin(system, [:queues, x]), get(config, :queues)))
  )

  buffer = vk.unwrap(vk.create_buffer(dev, bci))

  memreq = vk.get_buffer_memory_requirements(dev, buffer)

  req = ds.hashmap(
    :typemask, memreq.memory_type_bits,
    :flags, get(config, :memoryflags)
  )

  memtype = findmemtype(system, req)

  memory = vk.unwrap(vk.allocate_memory(dev, memreq.size, memtype[2]))

  vk.unwrap(vk.bind_buffer_memory(dev, buffer, memory, 0))

  hashmap(:buffer, buffer, :memory, memory, :size, memreq.size)
end

function transferbuffer(system, size)
  buffer(
    system,
    ds.hashmap(
      :size, size,
      :usage, vk.BUFFER_USAGE_TRANSFER_SRC_BIT,
      :mode, vk.SHARING_MODE_EXCLUSIVE,
      :queues, [:transfer],
      :memoryflags, vk.MEMORY_PROPERTY_HOST_COHERENT_BIT |
                    vk.MEMORY_PROPERTY_HOST_VISIBLE_BIT
    )
  )
end

function commandbuffers(system, n::Int, qf, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  pool = getpool(system, qf)

  buffers = vk.unwrap(vk.allocate_command_buffers(
    get(system, :device),
    vk.CommandBufferAllocateInfo(pool, level, n)
  ))
end

function commands(body, system, qf, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  pool = getpool(system, qf)
  queue = getqueue(system, qf)

  cmds = commandbuffers(system, 1, qf, level)
  cmd = cmds[1]

  vk.begin_command_buffer(cmd, vk.CommandBufferBeginInfo())

  body(cmd)

  vk.end_command_buffer(cmd)

  vk.queue_submit(queue, [vk.SubmitInfo([],[],[cmd],[])])

  vk.queue_wait_idle(queue)

  vk.free_command_buffers(get(system, :device), pool, cmds)
end

function copybuffer(system, src, dst, size, queuefamily=:transfer)
  commands(system, queuefamily) do cmd
    vk.cmd_copy_buffer(cmd, src, dst, [vk.BufferCopy(0,0,size)])
  end
end

function copybuffertoimage(system, src, dst, size, qf=:transfer)
  commands(system, qf) do cmd
    vk.cmd_copy_buffer_to_image(
      cmd,
      src,
      dst,
      vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
      [vk.BufferImageCopy(
        0, 0, 0,
        vk.ImageSubresourceLayers(vk.IMAGE_ASPECT_COLOR_BIT, 0, 0, 1),
        vk.Offset3D(0,0,0),
        vk.Extent3D(size..., 1)
      )]
    )
  end
end

accessmasks = hashmap(
  [vk.IMAGE_LAYOUT_UNDEFINED, vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL],
  hashmap(
    :srcam, vk.AccessFlag(0),
    :dstam, vk.ACCESS_TRANSFER_WRITE_BIT,
    :srcstage, vk.PIPELINE_STAGE_TOP_OF_PIPE_BIT,
    :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT
  ),
  [
    vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    vk.IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL
  ],
  hashmap(
    :srcam, vk.ACCESS_TRANSFER_WRITE_BIT,
    :dstam, vk.ACCESS_SHADER_READ_BIT,
    :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
    :dststage, vk.PIPELINE_STAGE_FRAGMENT_SHADER_BIT
  ),
    [
    vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
    vk.IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL
  ],
  hashmap(
    :srcam, vk.ACCESS_TRANSFER_WRITE_BIT,
    :dstam, vk.ACCESS_TRANSFER_WRITE_BIT,
    :srcstage, vk.PIPELINE_STAGE_TRANSFER_BIT,
    :dststage, vk.PIPELINE_STAGE_TRANSFER_BIT,
  )

)

function transitionimage(system, config)
  masks = get(accessmasks, [get(config, :srclayout), get(config, :dstlayout)])

  barrier = vk.unwrap(vk.ImageMemoryBarrier(
    get(masks, :srcam, vk.AccessFlag(0)),
    get(masks, :dstam, vk.AccessFlag(0)),
    get(config, :srclayout),
    get(config, :dstlayout),
    get(config, :srcqueue, vk.QUEUE_FAMILY_IGNORED),
    get(config, :dstqueue, vk.QUEUE_FAMILY_IGNORED),
    get(config, :image),
    vk.ImageSubresourceRange(vk.IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1)
  ))

  commands(system, get(config, :qf, :transfer)) do cmd
    vk.cmd_pipeline_barrier(
      cmd, [], [], [barrier];
      src_stage_mask=get(masks, :srcstage, 0),
      dst_stage_mask=get(masks, :dststage, 0)
    )
  end

end

function createimage(system, config)
  dev = get(system, :device)

  queues::Vector{UInt32} = ds.into(
    [], map(x -> ds.getin(system, [:queues, x])), get(config, :queues)
  )

  sharingmode = get(config, :sharingmode,
    length(queues) == 1 ? vk.SHARING_MODE_EXCLUSIVE : vk.SHARING_MODE_CONCURRENT
  )

  image = vk.unwrap(vk.create_image(
    dev,
    vk.IMAGE_TYPE_2D,
    get(config, :format),
    vk.Extent3D(get(config, :size)..., 1),
    1,
    1,
    vk.SAMPLE_COUNT_1_BIT,
    get(config, :tiling, vk.IMAGE_TILING_OPTIMAL),
    get(config, :usage),
    sharingmode,
    queues,
    get(config, :layout, vk.IMAGE_LAYOUT_UNDEFINED)
  ))

  memreq = vk.get_image_memory_requirements(dev, image)

  memory = vk.unwrap(vk.allocate_memory(
    dev,
    memreq.size,
    findmemtype(system, ds.hashmap(
      :typemask, memreq.memory_type_bits,
      :flags, get(config, :memoryflags)
    ))[2]
  ))

  vk.unwrap(vk.bind_image_memory(dev, image, memory, 0))

  hashmap(:image, image, :memory, memory, :size, memreq.size)
end

function texturesampler(system, config)
  props = vk.get_physical_device_properties(get(system, :physicaldevice))
  anis = props.limits.max_sampler_anisotropy

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
    anis,
    false,
    vk.COMPARE_OP_ALWAYS,
    0,
    0,
    vk.BORDER_COLOR_INT_OPAQUE_BLACK,
    false
  ))
end

end
