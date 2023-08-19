module hardware

import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, hashmap, assoc, into, emptyvector, emptymap

function containsall(needles, hay)::Bool
  return [nothing] == indexin([nothing], indexin(needles, hay))
end

function instance(config)
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

  if ds.containsp(config, :debuginfo)
    return vk.create_instance(
      validationlayers,
      extensions;
      next=get(config, :debuginfo),
      application_info=appinfo
    )
  else
    return vk.create_instance(
      validationlayers,
      extensions;
      application_info=appinfo
    )
  end
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


function checkdevice(config, system)
  pdev = get(system, :physicaldevice)
  # props = vk.get_physical_device_properties(pdev)
  # features = vk.get_physical_device_features(pdev)

  return getin(system, [:queues, :graphics]) !== nothing && getin(system, [:queues, :presentation]) !== nothing && swapchainsupport(system) && containsall(
           getin(config, [:device, :extensions]),
           map(
             x -> x.extension_name,
             vk.unwrap(vk.enumerate_device_extension_properties(pdev))
           )
         ) && containsall(
           getin(config, [:device, :validation]),
           map(
             x -> x.layer_name,
             vk.unwrap(vk.enumerate_device_layer_properties(pdev))
           )
         )
end

function findformat(config, system)
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

function findextent(config, system)
  vk.Extent2D(
    getin(config, [:window, :width]),
    getin(config, [:window, :height])
  )
end

function findpresentmode(config, system)
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
    :presentation, findpresentationqueue(system, device)
  )
end

function pdevice(config, system)
  potential = into(
    emptyvector,
    map(x -> merge(system, hashmap(
      :physicaldevice, x,
      :queues, findqueues(system, x)
    ))) ∘
    filter(x -> checkdevice(config, x)),
    vk.unwrap(vk.enumerate_physical_devices(get(system, :instance)))
  )

  if ds.emptyp(potential)
    nothing
  else
    first(potential)
  end
end

function getqueue(system, queue)
  i = get(get(system, :queues), queue)
  return vk.get_device_queue(get(system, :device), i, 0)
end

function createdevice(config, system)
  system = pdevice(config, system)
  queues = get(system, :queues)
  pdev = get(system, :physicaldevice)

  qs2c = ds.vals(
    into(emptymap, map(x -> ds.MapEntry(x, x)), ds.vals(queues))
  )
  qcis::Base.Vector = map(x -> vk.DeviceQueueCreateInfo(x, [1.0]), qs2c)

  dci = vk.DeviceCreateInfo(
    qcis,
    getin(config, [:device, :validation], []),
    getin(config, [:device, :extensions], [])
  )

  assoc(system, :device, vk.unwrap(vk.create_device(pdev, dci)))
end

function createswapchain(config, system)
  format = findformat(config, system)
  sc = vk.create_swapchain_khr(
    get(system, :device),
    get(system, :surface),
    getin(config, [:swapchain, :images]),
    format.format,
    format.color_space,
    findextent(config, system),
    1, # image arrays
    vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    vk.SHARING_MODE_EXCLUSIVE, # <- FIXME: don't hardcode this
    [],
    vk.SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
    vk.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    findpresentmode(config, system),
    true
  )
  assoc(system, :swapchain, vk.unwrap(sc))
end

function createimageviews(config, system)
  dev = get(system, :device)
  images = vk.unwrap(vk.get_swapchain_images_khr(dev, get(system, :swapchain)))

  into(
    emptyvector,
    map(image -> vk.create_image_view(
      dev,
      image,
      vk.IMAGE_VIEW_TYPE_2D,
      findformat(config, system).format,
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
    )) ∘
    map(vk.unwrap),
    images
  )
end

end
