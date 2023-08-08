import GLFW.GLFW as glfw
import Vulkan as vk
import BitMasks

function window()

    glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
    glfw.WindowHint(glfw.RESIZABLE, true)

  w = glfw.CreateWindow(800, 600, "not quite a browser")

  @async begin
    while !glfw.WindowShouldClose(w)
      glfw.PollEvents()
      sleep(2)
    end

    glfw.DestroyWindow(w)
  end

  return w
end

# w = window()


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

function debugcb(severity, type, data::Ptr{dumcd}, userData)
  d = unsafe_load(data)

  msg = unsafe_string(d.pMessage)
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

function debugmsg(instance)
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

inst = vk.unwrap(instance(extensions, validationlayers; debuginfo))

msgr = vk.unwrap(debugmsg(inst))
