import brow
import GLFW.GLFW as glfw
import Vulkan as vk
import DataStructures as ds
import DataStructures: getin, hashmap, assoc, into

glfw.Init()

function createwindow(config)
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, true)

  glfw.CreateWindow(
    getin(config, [:window, :height]),
    getin(config, [:window, :width]),
    "not quite a browser"
  )
end

function containsall(needles, hay)::Bool
  return [nothing] == indexin([nothing], indexin(needles, hay))
end

LogLevel = (
  debug=vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
  info= vk.DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
  warn= vk.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
  error=vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
)

LogLevel = merge(
  LogLevel,
  (all=LogLevel.debug|LogLevel.info|LogLevel.warn|LogLevel.error,)
)

LogType = (
  general=    vk.DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT,
  validation= vk.DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
  performance=vk.DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
)

LogType = merge(
  LogType,
  (all=LogType.general|LogType.validation|LogType.performance,)
)

dumcd = vk.vk.LibVulkan.VkDebugUtilsMessengerCallbackDataEXT

function debugcb(severity, type, datap::Ptr{dumcd}, userData)
  data = unsafe_load(datap)

  msg = unsafe_string(data.pMessage)
  if severity == LogLevel.error.val
    @error msg
  elseif severity == LogLevel.warn.val
    @warn msg
  elseif severity == LogLevel.info.val
    @info msg
  elseif severity == LogLevel.debug.val
    @debug msg
  end
  return false
end

function debugmsgr(config, system)
  vk.create_debug_utils_messenger_ext(
    get(system, :instance),
    get(config, :debuginfo)
  )
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
    v"1.2";
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
      0:length(vk.get_physical_device_queue_family_properties(device)) - 1
    )
  )
end

function checkdevice(config, system)
  # props = vk.get_physical_device_properties(device)
  # features = vk.get_physical_device_features(device)
  supportedextensions = vk.unwrap(
    vk.enumerate_device_extension_properties(get(system, :physicaldevice))
  )

  return getin(system, [:queues, :graphics]) !== nothing &&
    getin(system, [:queues, :presentation]) !== nothing &&
    containsall(
      getin(config, [:device, :extensions]),
      map(x -> x.extension_name, supportedextensions)
    )
end

function findqueues(system, device)
  ds.hashmap(
    :graphics, findgraphicsqueue(device),
    :presentation, findpresentationqueue(system, device)
  )
end

function pdevice(config, system)
  potential = into(
    ds.emptyvector,
    map(x -> merge(system, hashmap(
      :physicaldevice, x,
      :queues, findqueues(system, x)
    ))) ∘
    filter(x -> checkdevice(config, x)),
    vk.unwrap(vk.enumerate_physical_devices(get(system, :instance)))
  )

  @info typeof(potential)
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

function swapchainsupport(system)
  dev = get(system, :physicaldevice)
  surface = get(system, :surface)

  capabilities = vk.get_physical_device_surface_capabilities_khr(dev, surface)
  formats = vk.get_physical_device_surface_formats_khr(dev, surface)
  modes = vk.get_physical_device_surface_present_modes_khr(dev, surface)
end

function createdevice(config, system)
  system = pdevice(config, system)
  queues = get(system, :queues)
  pdev = get(system, :physicaldevice)

  qs2c = ds.vals(ds.into(ds.emptymap, map(x -> ds.MapEntry(x, x)), ds.vals(queues)))
  qcis::Base.Vector = map(x -> vk.DeviceQueueCreateInfo(x, [1.0]), qs2c)

  dci = vk.DeviceCreateInfo(
    qcis,
    getin(config, [:device, :validation], []),
    getin(config, [:device, :extensions], [])
  )

  assoc(system, :device, vk.unwrap(vk.create_device(pdev, dci)))
end

config = hashmap(
  :instance, hashmap(
    :extensions,
    vcat(glfw.GetRequiredInstanceExtensions(), ["VK_EXT_debug_utils"]),
    :validation, ["VK_LAYER_KHRONOS_validation"]
  ),
  :device, hashmap(
    :extensions, [vk.VK_KHR_SWAPCHAIN_EXTENSION_NAME],
    :validation, ["VK_LAYER_KHRONOS_validation"]
  ),
  :debuginfo, vk.DebugUtilsMessengerCreateInfoEXT(
    LogLevel.all,
    LogType.all,
    @cfunction(
      debugcb,
      Bool,
      (Cuint, Cuint, Ptr{dumcd}, Ptr{Cvoid}))
  ),
  :window, hashmap(:width, 1080, :height, 1920)
)

function init(config)
  system = hashmap(:instance, vk.unwrap(instance(config)))
  system = assoc(system, :debugmsgr, vk.unwrap(debugmsgr(config, system)))
  system = assoc(system, :window, createwindow(config))
  system = assoc(system, :surface, glfw.CreateWindowSurface(
    get(system, :instance),
    get(system, :window)
  ))

  system = createdevice(config, system)
  return system
end

system = init(config)


function repl_teardown()
  # This should destroy all windows, surfaces, etc., no need to go through them
  # one by one.
  glfw.Terminate()
end
