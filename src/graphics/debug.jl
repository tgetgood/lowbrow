module debug

import Vulkan as vk
import DataStructures: assoc

LogLevel = (
  debug=vk.DEBUG_UTILS_MESSAGE_SEVERITY_VERBOSE_BIT_EXT,
  info=vk.DEBUG_UTILS_MESSAGE_SEVERITY_INFO_BIT_EXT,
  warn=vk.DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT,
  error=vk.DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT
)

LogLevel = merge(
  LogLevel,
  (all=LogLevel.debug | LogLevel.info | LogLevel.warn | LogLevel.error,)
)

LogType = (
  general=vk.DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT,
  validation=vk.DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT,
  performance=vk.DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT,
)

LogType = merge(
  LogType,
  (all=LogType.general | LogType.validation | LogType.performance,)
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

function debuginfo()
  vk.DebugUtilsMessengerCreateInfoEXT(
    LogLevel.all,
    LogType.all,
    @cfunction(
      debugcb,
      Bool,
      (Cuint, Cuint, Ptr{dumcd}, Ptr{Cvoid}))
  )
end

function debugmsgr(config, system)
  assoc(system, :debugmsgr,
    vk.unwrap(
      vk.create_debug_utils_messenger_ext(
        get(system, :instance),
        get(config, :debuginfo)
      )
    )
  )
end

end
