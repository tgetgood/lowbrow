import brow
import GLFW.GLFW as glfw
import Vulkan as vk
import DataStructures as ds

glfw.Init()

function createwindow()
    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, true)

  w = glfw.CreateWindow(800, 600, "not quite a browser")

  # @async begin
  #   while !glfw.WindowShouldClose(w)
  #     glfw.PollEvents()
  #     sleep(2)
  #   end
  # end

  return w
end

extensions = vcat(
  glfw.GetRequiredInstanceExtensions(),
  ["VK_EXT_debug_utils"]
)

validationlayers = ["VK_LAYER_KHRONOS_validation"]

function containsall(needles, hay)
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

debuginfo = vk.DebugUtilsMessengerCreateInfoEXT(
  LogLevel.all,
  LogType.all,
  @cfunction(
    debugcb,
    Bool,
    (Cuint, Cuint, Ptr{dumcd}, Ptr{Cvoid}))
)

function debugmsgr(instance)
  vk.create_debug_utils_messenger_ext(instance, debuginfo)
end


function instance(extensions, validations; debuginfo=nothing)
  @assert containsall(
    extensions,
    map(
      x -> x.extension_name,
      vk.unwrap(vk.enumerate_instance_extension_properties())
    )
  ) "unsupported extensions required."

  @assert containsall(
    validations,
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

  if debuginfo === nothing
    return vk.create_instance(
      validationlayers,
      extensions;
      application_info=appinfo)
  else
    return vk.create_instance(
      validationlayers,
      extensions;
      next=debuginfo,
      application_info=appinfo
    )
    end
end

function devicegraphicsqueue(system)
  vk.get_device_queue(
    get(system, :device),
    vk.find_queue_family(get(system, :physicaldevice), vk.QUEUE_GRAPHICS_BIT),
    0
  )
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

function checkdevice(system, device, queues)
  # props = vk.get_physical_device_properties(device)
  # features = vk.get_physical_device_features(device)

  return get(queues, :graphics) !== nothing &&
    get(queues, :presentation) !== nothing
end

function findqueues(system, device)
  ds.hashmap(
    :graphics, findgraphicsqueue(device),
    :presentation, findpresentationqueue(system, device)
  )
end

function pdevice(system)
  devs =
    filter(
      x -> checkdevice(system, x[1], x[2]),
      map(
        x -> [x, findqueues(system, x)],
        vk.unwrap(vk.enumerate_physical_devices(get(system, :instance)))
      )
    )

  if length(devs) == 0
    nothing
  else
    first(devs)
  end
end

function createdevice(system)
  (pdev, queues) = pdevice(system)

  qci = vk.DeviceQueueCreateInfo(
    vk.find_queue_family(pdev, vk.QUEUE_GRAPHICS_BIT),
    [1.0]
  )
  dci = vk.DeviceCreateInfo(
    [qci],
    validationlayers,
    []
  )
  dev = vk.unwrap(vk.create_device(pdev, dci))

  return merge(system, ds.hashmap(:physicaldevice, pdev, :device, dev, :queues, queues))
end

function start(system)
  inst = vk.unwrap(instance(extensions, validationlayers; debuginfo))
  debug = vk.unwrap(debugmsgr(inst))
  w = createwindow()
  surface = glfw.CreateWindowSurface(inst, w)

  system = merge(
    system,
    ds.hashmap(
      :instance, inst,
      :debugmsgr, debug,
      :window, w,
      :surface, surface
    ))

  system = createdevice(system)
  return system
end

system = start(ds.emptyorderedmap)


function repl_teardown()
  # This should destroy all windows, surfaces, etc., no need to go through them
  # one by one.
  glfw.Terminate()
end
