"""
Wrappers for querying hardware.
"""
module hardware

import Glfw as window

import Vulkan as vk
import DataStructures as ds
import DataStructures: get, getin, assoc, hashmap, into, emptyvector, emptymap, emptyset

import resources as rd
import resources: bufferusagebits, memorypropertybits, sharingmodes, imageusagebits

"""
Returns a hashmap isomorphic to s. It's probably better to override fns for
vk.HighLevelStruct to treat them like maps, rather than actually cast
everything.
"""
function srecord(s::T) where T
  into(emptymap, map(k -> (k, getproperty(s, k))), fieldnames(T))
end

function xrel(s::Vector{T}) where T
  into(emptyset, map(srecord), s)
end

function instanceinfo()
  hashmap(
    :version, vk.unwrap(vk.enumerate_instance_version()),
    :extensions, xrel(vk.unwrap(vk.enumerate_instance_extension_properties())),
    :layers, xrel(vk.unwrap(vk.enumerate_instance_layer_properties()))
  )
end

function swapchainsupport(surfaceinfo)
  formats = get(surfaceinfo, :formats)
  modes = get(surfaceinfo, :present_modes)
  return length(formats) > 0 && length(modes) > 0
end

function findformat(spec)
  filtered = filter(
    x -> x.format == spec.swapchain.format &&
      x.color_space == spec.swapchain.colourspace,
    spec.surface.formats
  )

  if length(filtered) == 0
    nothing
  else
    first(filtered)
  end
end

function findextent(system)
  sc = system.spec.surface.capabilities

  win = window.size(system.window)

  vk.Extent2D(
    clamp(win.width, sc.min_image_extent.width, sc.max_image_extent.width),
    clamp(win.height, sc.min_image_extent.height, sc.max_image_extent.height)
  )
end

function findpresentmode(spec)
  modes = spec.surface.present_modes

  if length(modes) == 0
    nothing
  else
    first(modes)
  end
end

function multisamplemax(spec, samples)
  limits = spec.device.properties.limits
  depth = limits.framebuffer_depth_sample_counts
  colour = limits.framebuffer_color_sample_counts

  vk.SampleCountFlag(
    1 << (ndigits((depth&colour&(2*samples - 1)).val, base=2) - 1)
  )
end

const featuretypes = hashmap(
  v"1.3", vk.PhysicalDeviceVulkan13Features,
  v"1.2", vk.PhysicalDeviceVulkan12Features,
  v"1.1", vk.PhysicalDeviceVulkan11Features,
  v"1.0", vk.PhysicalDeviceFeatures2
)

function devicefeatures(pdev)
  ds.mapvals(x -> vk.get_physical_device_features_2(pdev, x).next, featuretypes)
end

function surfaceinfo(pdev, surface)
  ds.hashmap(
    :formats, vk.unwrap(
      vk.get_physical_device_surface_formats_khr(pdev; surface)
    ),
    :capabilities, vk.unwrap(
      vk.get_physical_device_surface_capabilities_khr(pdev, surface)
    ),
    :present_modes, vk.unwrap(
      vk.get_physical_device_surface_present_modes_khr(pdev; surface)
    ),
    :presentation_qfs, into(ds.emptyset,
      filter(i -> vk.unwrap(vk.get_physical_device_surface_support_khr(
          pdev,
          i,
          surface
        )),
        0:length(vk.get_physical_device_queue_family_properties(pdev))-1)
    )
  )
end

function physicaldeviceinfo(pdev)
  ds.hashmap(
    :qf_properties, vk.get_physical_device_queue_family_properties(pdev),
    :memoryproperties, vk.get_physical_device_memory_properties(pdev),
    :properties, vk.get_physical_device_properties(pdev),
    :extensions, xrel(vk.unwrap(vk.enumerate_device_extension_properties(pdev))),
    :layers, xrel(vk.unwrap(vk.enumerate_device_layer_properties(pdev))),
    :features, devicefeatures(pdev)
  )
end

function physicaldevices(instance, surface)
  into(
    emptymap,
    map(x -> [
      x,
      hashmap(
        :surface, surfaceinfo(x, surface),
        :device, physicaldeviceinfo(x)
      )
    ]),
    vk.unwrap(vk.enumerate_physical_devices(instance))
  )
end

function createswapchain(system, config)
  format = findformat(system.spec)
  extent = findextent(system)

  # TODO: Use createinfo structs. Stop relying on Vulkan.jl wrapper functions
  # since I'm probably going to stop using it.
  # sci = vk._SwapchainCreateInfoKHR(

  # )

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
    findpresentmode(system.spec),
    true;
    old_swapchain=get(system, :swapchain, C_NULL)
  )

  hashmap(:swapchain, vk.unwrap(sc), :extent, extent, :format, format)
end

function imageview(system, config, image)
  vk.unwrap(vk.create_image_view(
    get(system, :device),
    get(image, :image),
    vk.IMAGE_VIEW_TYPE_2D,
    get(config, :format),
    vk.ComponentMapping(
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY,
      vk.COMPONENT_SWIZZLE_IDENTITY
    ),
    vk.ImageSubresourceRange(
      get(config, :aspect, vk.IMAGE_ASPECT_COLOR_BIT),
      0,
      get(image, :miplevels, 1),
      0,
      1
    )
  ))
end

function commandpool(dev, qf, flags=vk.CommandPoolCreateFlag(0))
  vk.unwrap(vk.create_command_pool(dev, qf; flags=flags))
end

function findmemtype(spec, config)
  properties = spec.device.memoryproperties
  mask = config.typemask
  flags = config.flags

  mt = into(
    [],
    ds.mapindexed((i, x) -> (x, i-1))
    ∘ filter(x -> (mask & (1 << x[2])) > 0)
    ∘ filter(x -> (x[1].property_flags & flags) == flags)
    ,
    properties.memory_types[1:properties.memory_type_count]
  )

  @assert length(mt) > 0

  mt[1]
end

function buffer(system, config)
  dev = system.device

  queues = into(
    ds.emptyset,
    map(x -> get(system.spec.queues.queue_families, x)),
    get(config, :queues)
  )

  mode = get(sharingmodes, get(config, :sharingmode,
    ds.count(queues) == 1 ? :exclusive : :concurrent
  ))

  bci = vk.BufferCreateInfo(
    get(config, :size),
    vk.BufferUsageFlag(rd.orlist(bufferusagebits, config.usage)),
    mode,
    into([], queues)
  )

  buffer = vk.unwrap(vk.create_buffer(dev, bci))

  memreq = vk.get_buffer_memory_requirements(dev, buffer)

  req = ds.hashmap(
    :typemask, memreq.memory_type_bits,
    :flags, rd.orlist(memorypropertybits, get(config, :memoryflags))
  )

  # TODO: There's a lot of confusion about who's responsibility it is to dig
  # into the info struct for the correct element. I'm not sure about this.
  #
  # For now I'm going to treat it as a globalish immutable that can't be static
  # because it must be negotiated at runtime.
  memtype = findmemtype(system.spec, req)

  memory = vk.unwrap(vk.allocate_memory(dev, memreq.size, memtype[2]))

  vk.unwrap(vk.bind_buffer_memory(dev, buffer, memory, 0))

  hashmap(:buffer, buffer, :memory, memory, :size, memreq.size)
end

function transferbuffer(system, size)
  buffer(
    system,
    ds.hashmap(
      :size, size,
      :usage, [:transfer_src, :transfer_dst],
      :queues, [:transfer],
      :memoryflags, [:host_coherent, :host_visible]
    )
  )
end

function commandbuffers(
  dev::vk.Device, pool::vk.CommandPool, n::Int, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY
)
  vk.unwrap(
    vk.allocate_command_buffers(dev, vk.CommandBufferAllocateInfo(pool, level, n))
  )
end

function commandbuffer(dev, pool, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  commandbuffers(dev, pool, 1, level)[1]
end

function commandbuffers(system, n::Int, qf, level=vk.COMMAND_BUFFER_LEVEL_PRIMARY)
  commandbuffers(get(system, :device), getpool(system, qf), n, level)
end

function createimage(system, config)
  dev = system.device
  samples = get(config, :samples, vk.SAMPLE_COUNT_1_BIT)

  queues::Vector{UInt32} = ds.into(
    [], map(x -> get(system.spec.queues.queue_families, x)), config.queues
  )

  sharingmode = get(sharingmodes, get(config, :sharingmode,
    length(queues) == 1 ? :exclusive : :concurrent
  ))

  ex = findextent(system)

  image = vk.unwrap(vk.create_image(
    dev,
    vk.IMAGE_TYPE_2D,
    config.format,
    vk.Extent3D(config.size..., 1),
    get(config, :miplevels, 1),
    1,
    samples,
    get(config, :tiling, vk.IMAGE_TILING_OPTIMAL),
    rd.orlist(imageusagebits, config.usage),
    sharingmode,
    queues,
    get(config, :layout, vk.IMAGE_LAYOUT_UNDEFINED)
  ))

  memreq = vk.get_image_memory_requirements(dev, image)

  memory = vk.unwrap(vk.allocate_memory(
    dev,
    memreq.size,
    findmemtype(system.spec, ds.hashmap(
      :typemask, memreq.memory_type_bits,
      :flags, rd.orlist(memorypropertybits, config.memoryflags)
    ))[2]
  ))

  vk.unwrap(vk.bind_image_memory(dev, image, memory, 0))

  hashmap(
    :image, image,
    :memory, memory,
    :size, memreq.size,
    :miplevels, get(config, :miplevels, 1),
    :samples, samples,
    :format, get(config, :format),
    :resolution, get(config, :size)
  )
end

function colourresources(system, config)
  format = system.spec.swapchain.format
  ext = findextent(system)

  image = createimage(system, hashmap(
    :size, [ext.width, ext.height],
    :format, format,
    :samples, multisamplemax(system.spec, config.samples),
    :memoryflags, :device_local,
    # FIXME: Negotiate with host and allow optional flags. Lazy allocation is an
    # optimisation which might or might not be supported. We want to use it if
    # it's available.
    # :memoryflags, [:device_local, :lazy],
    :queues, [:graphics],
    :usage, [:transient, :colour]
  ))

  view = imageview(system, hashmap(:format, format), image)

  assoc(image, :view, view)
end

function finddepthformats(system, config)
  function getfeats(x)
    t = get(config, :tiling)
    if t == vk.IMAGE_TILING_LINEAR
      x.linear_tiling_features
    elseif t == vk.IMAGE_TILING_OPTIMAL
      x.optimal_tiling_features
    end
  end

  candidates = ds.into(
    [],
    # FIXME: We should do all of this querying at device creation time.
    map(x -> (x, vk.get_physical_device_format_properties(system.pdev, x)))
    ∘
    filter(x -> (config.features & getfeats(x[2])) > 0),
    config.formats
  )

  @assert length(candidates) > 0

  return first(candidates)[1]
end

optdepthformat(system) = finddepthformats(
  system,
  hashmap(
    :tiling, vk.IMAGE_TILING_OPTIMAL,
    :features, vk.FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT,
    :formats, [
      vk.FORMAT_D32_SFLOAT,
      vk.FORMAT_D24_UNORM_S8_UINT,
      vk.FORMAT_D32_SFLOAT_S8_UINT,
    ]
  )
)

function depthresources(system, config)
  format = optdepthformat(system)
  ex = findextent(system)

  image = createimage(system,
    hashmap(
      :tiling, vk.IMAGE_TILING_OPTIMAL,
      :format, format,
     :samples, multisamplemax(system.spec, config.samples),
      :size, [ex.width, ex.height],
      :usage, [:depth_stencil, :transient],
      :queues, [:graphics],
      :memoryflags, :device_local
    )
  )

  view = imageview(
    system,
    hashmap(
      :format, format,
      :aspect, vk.IMAGE_ASPECT_DEPTH_BIT
    ),
    image
  )

  assoc(image, :view, view)
end

function createimageviews(system, config)
  dev = get(system, :device)

  hashmap(
    :imageviews, into(
      emptyvector,
      map(image -> imageview(
        system,
        hashmap(:format, findformat(system.spec).format),
        hashmap(:image, image)
      )),
      vk.unwrap(vk.get_swapchain_images_khr(dev, get(system, :swapchain)))
    ),
    :depth, depthresources(system, config),
    :colour, colourresources(system, config)
  )
end

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

end
