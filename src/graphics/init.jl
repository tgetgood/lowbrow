module init

import Vulkan as vk
import DataStructures as ds

import debug
import resources as rd
import hardware as hw

################################################################################
##### Default app config
################################################################################

VS = Union{Vector, ds.Vector}

mergeconfig(x, y) = y
mergeconfig(x::ds.Map, y::ds.Map) = ds.mergewith(mergeconfig, x, y)
mergeconfig(x::VS, y::VS) = ds.into(y, x)
mergeconfig(x, ys...) = ds.reduce(mergeconfig, x, ys)

defaults = ds.hashmap(
  :dev_tools, true,
  :debuglevel, :warning,
  :name, "",
  :version, v"0.0.0",
  :engine, ds.hashmap(
    :version, v"0.0.1",
    :name, "unnamed",
  ),
  :instance, ds.hashmap(
    :vulkan_version, v"1.3.276"
  ),
  :device, ds.hashmap(
    :features, ds.hashmap(
      # v"1.0", [:sampler_anisotropy],
      v"1.2", [:timeline_semaphore],
      v"1.3", [:synchronization2],
    ),
    # FIXME: logically these are sets. How does vk handle repeats?
    :extensions, ["VK_KHR_swapchain"]
  ),
  :window, (width=1200, height=1200),
  :render, ds.hashmap(
    :msaa, 1, # Disabled
    :swapchain, ds.hashmap(
      # TODO: Fallback formats and init time selection.
      :format, vk.FORMAT_B8G8R8A8_SRGB,
      :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
      :presentmode, vk.PRESENT_MODE_FIFO_KHR,
      :images, 3
    )
  ),
  :concurrent_frames, 3
)

devtooling = ds.hashmap(
  :instance, ds.hashmap(
    :extensions, ["VK_EXT_debug_utils"],
    :layers, ["VK_LAYER_KHRONOS_validation"]
  ),
  :device, ds.hashmap(
    :layers, ["VK_LAYER_KHRONOS_validation"]
  )
)

################################################################################
##### Negotiation with drivers/hardware
################################################################################

"""
Returns true if every element in requested is also in available.
Returns false and logs a warning if there are missing dependencies.

N.B.: it fails soft because it's up to downstream components to decide if they
can or cannot continue without the requested features/layers/extensions.
"""
function checkavailability(requested, available, k, name)
  # Unrequested features shouldn't be activated, but that's not an error by
  # current reckoning.
  # REVIEW: Maybe it should be...
  diff = ds.difference(ds.project(requested, [k]), ds.project(available, [k]))
  if diff === ds.emptyset
    true
  else
    msg = ds.into("", map(x -> get(x, k)) ∘ map(string) ∘ ds.interpose(", "), diff)
    @warn "The following requested "* name * " are not supported:\n" * msg
    return false
  end
end

function torel(key, seq)
  ds.into(ds.emptyset, map(x -> ds.hashmap(key, x)), seq)
end

"""
Parses the program config and infers all requirements on the instance level.
"""
function instancerequirements(config)
  appmeta = ds.hashmap(
    :app, ds.selectkeys(config, [:version, :name]),
    :engine, get(config, :engine)
  )

  info = hw.instanceinfo()
  ic = get(config, :instance)
  api_version = get(ic, :vulkan_version)

  layers = torel(:layer_name, get(ic, :layers, []))
  extensions = torel(:extension_name, get(ic, :extensions, []))

  supported_layers = ds.join(layers, get(info, :layers))
  supported_extensions = ds.join(extensions, get(info, :extensions))

  checkavailability(layers, supported_layers, :layer_name, "layers")

  checkavailability(
    extensions, supported_extensions, :extension_name, "extensions"
  )

  version = get(info, :version)

  if version < api_version
    @warn "Vulkan api version " * string(api_version) *
      " requested, but the driver only supports " * string(version)
    api_version = version
  end

  spec = ds.assoc(appmeta,
    :version, api_version,
    :extensions, supported_extensions,
    :layers, supported_layers
  )

  # REVIEW: Is this where I want to set up debug logging?
  # It can't be overridden like this, only disabled.
  if get(config, :dev_tooling, false)
    ds.assoc(spec, :debuginfo,
      debuginfo(
        get(rd.debugutilsseveritybits, get(config, :debuglevel, :info)).val
      )
    )
  else
    spec
  end
end

################################################################################
##### Resource creation
################################################################################

function instance(config)
  appinfo = vk.ApplicationInfo(
    ds.getin(config, [:app, :version]),
    ds.getin(config, [:engine, :version]),
    get(config, :version);
    application_name=ds.getin(config, [:app, :name]),
    engine_name=ds.getin(config, [:engine, :name])
  )

  vk.unwrap(vk.create_instance(
    ds.into!([], map(x -> get(x, :layer_name)), get(config, :layers)),
    ds.into!([], map(x -> get(x, :extension_name)), get(config, :extensions));
    next=get(config, :debuginfo, C_NULL),
    application_info=appinfo
  ))
end

################################################################################
##### Entrypoint
################################################################################

# REVIEW: Takes in a module which provides an OS window. The idea is to be able
# to swap glfw for sdl when required, but I need to standardise the api before
# that's realistic.
function setup(baseconfig, wm)
  windowconfig = wm.configure()

  config = mergeconfig(defaults, baseconfig, windowconfig)

  # The general flow is that you specify what you want in config, call a
  # negotiator which returns the best you can get, and if that's good enough,
  # you pass that info on to the creation fns.
  instinfo = instancerequirements(config)

  inst = instance(instinfo)

  debugmessenger = debug.debugmsgr(inst, get(instinfo, :debuginfo, nothing))

  window, resizecb = wm.window(
    get(config, :window),
    get(config, :name)
  )

  surface = wm.surface(inst, window)

  pdevs = hw.physicaldevices(inst, surface)

  system = ds.hashmap(
    :instance, inst,
    :window, window,
    # REVIEW: Include the windowmanager here? Or wrap the window object in a
    # struct that can query its size and whatnot?
    :surface, surface,
    :pdevs, pdevs
  )
end

end # module