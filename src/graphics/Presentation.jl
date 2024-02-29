module Presentation

import Vulkan as vk
import DataStructures as ds

import Helpers: xrel

function swapchainrequirements(config, info)
  minimages = info.capabilities.min_image_count
  maximages = info.capabilities.max_image_count

  if maximages == 0
    # REVIEW: Is there an upper limit in the spec?
    maximages = typemax(UInt32)
  end

  images = clamp(config.images, minimages, maximages)

  present_modes = ds.set(info.present_modes...)

  supported_modes = filter(x -> ds.containsp(present_modes, x), config.present_mode)

  @assert length(supported_modes) > 0 "No supported present modes found."

  formats = xrel(info.formats)

  supported_formats = filter(x -> ds.containsp(formats, x), config.formats)

  @assert length(supported_formats) > 0 "No supported formats found."


  ds.hashmap(
    :format, first(supported_formats),
    :present_mode, first(supported_modes),
    :images, images
  )
end

function swapchain(system, extent, info)
  sc = vk.create_swapchain_khr(
    system.device,
    system.surface,
    info.images,
    info.format.format,
    info.format.color_space,
    extent,
    1, # image arrays
    vk.IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
    vk.SHARING_MODE_EXCLUSIVE, # <- FIXME: don't hardcode this
    [],
    vk.SURFACE_TRANSFORM_IDENTITY_BIT_KHR,
    vk.COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
    info.present_mode,
    true;
    old_swapchain=get(system, :swapchain, C_NULL)
  )

  ds.hashmap(:swapchain, vk.unwrap(sc))
end

end
