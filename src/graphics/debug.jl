module debug

import Vulkan as vk
import DataStructures: assoc, hashmap

dumcd = vk.vk.LibVulkan.VkDebugUtilsMessengerCallbackDataEXT

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


function debugcb(severity, type, datap::Ptr{dumcd}, userData::Ptr{Cvoid})
  data = unsafe_load(datap)

  msg = unsafe_string(data.pMessage)

  level = Base.cconvert(Int64, userData)

  if severity >= level
    if severity == LogLevel.error.val
      @error msg
    elseif severity == LogLevel.warn.val
      @warn msg
    elseif severity == LogLevel.info.val
      @info msg
    elseif severity == LogLevel.debug.val
      @debug msg
    end
  end

  return false
end

function debuginfo(level)
  data = Base.cconvert(Int64, level)
  user_data = Ptr{Cvoid}(data)

  vk.DebugUtilsMessengerCreateInfoEXT(
    LogLevel.all,
    LogType.all,
    @cfunction(
      debugcb,
      Bool,
      (Cuint, Cuint, Ptr{dumcd}, Ptr{Cvoid}));
    user_data
  )
end

function debugmsgr(instance, debuginfo)
  if debuginfo !== nothing
    vk.unwrap(vk.create_debug_utils_messenger_ext(instance, debuginfo))
  end
end

end
