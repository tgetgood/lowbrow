module init

import Vulkan as vk
import DataStructures as ds

import debug
import resources as rd
import hardware as hw

import pprint

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
      v"1.0", [],
      v"1.1", [],
      v"1.2", [:timeline_semaphore],
      v"1.3", [:synchronization2],
    ),
    # FIXME: logically these are sets. How does vk handle repeats?
    :extensions, ["VK_KHR_swapchain"]
  ),
  :window, ds.hashmap(
    :width, 1000,
    :height, 1000,
    :resizable, true,
    :interactive, true

  ),
  # TODO: Implement caching: I'm already suffering on the laptop.
  :cache_pipelines, true,
  :pipelines, ds.hashmap(
    :render, ds.hashmap(
      :type, :graphics,
      :msaa, 1, # Disabled
    ),
    :host_transfer, ds.hashmap(
      :type, :transfer
    )
  ),
  :headless, false,
  :swapchain, ds.hashmap(
    # TODO: Fallback formats and init time selection.
    :format, vk.FORMAT_B8G8R8A8_SRGB,
    :colourspace, vk.COLOR_SPACE_SRGB_NONLINEAR_KHR,
    :presentmode, vk.PRESENT_MODE_FIFO_KHR,
    :images, 2
  ))

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

N.B.: it fails soft by default because it's often up to downstream components to
decide if they can or cannot continue without the requested
features/layers/extensions.
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
    @warn "The following requested " * name * " are not supported:\n" * msg
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

function featuresupported(feature, supported)
  try
    getproperty(supported, feature)
  catch e
    @warn e
    false
  end
end

function featuressupported(required, supported)
  filter(f -> featuresupported(f, supported), required)
end

function featurediff(requested, supported)
  function rf(m, fe)
    s = ds.into(ds.emptyset, get(supported, ds.key(fe)))
    fs = ds.remove(f -> ds.containsp(s, f), ds.val(fe))
    if ds.count(fs) == 0
      m
    else
      ds.assoc(m, ds.key(fe), fs)
    end
  end
  ds.reduce(rf, ds.emptymap, requested)
end

function checkfeatures(requested, supported)
  if requested == supported
    true
  else
    msg = "The following requested Vulkan features are not supported by available hardware: "
    msg *= string(featurediff(requested, supported))
    @debug msg
    false
  end
end

function queuerequirements(config, info)
  qfp = ds.getin(info, [:device, :qf_properties])
  qtypes = [:transfer, :compute, :graphics]

  queue_families = ds.into(ds.emptymap, map(x -> hw.queuetype(qfp, x)), qtypes)

  pipelinecounts = ds.mapvals(
    ds.count,
    ds.groupby(x -> get(ds.val(x), :type), get(config, :pipelines))
  )

  queuecountbyfamily = ds.into(
    ds.emptymap,
    ds.mapvals(x -> ds.set(ds.keys(x)...))
    ∘
    ds.mapvals(x -> sum(ds.into!([], map(y -> get(pipelinecounts, y, 0)), x))),
    ds.groupby(ds.val, queue_families)
  )

  if !get(config, :headless, false)
    queue_families = ds.assoc(
      queue_families,
      :presentation,
      first(sort(ds.seq(ds.getin(info, [:surface, :presentation_qfs]))))
    )

    presqf = get(queue_families, :presentation)

    queuecountbyfamily = ds.assoc(
      queuecountbyfamily,
      presqf,
      get(queuecountbyfamily, presqf, 0) + 1
    )
  end

  supported_counts = map(
    x -> [ds.key(x), min(ds.val(x), qfp[ds.key(x) + 1].queue_count)],
    queuecountbyfamily
  )

  ds.hashmap(
    :queue_families, queue_families,
    :supported_counts, supported_counts
  )
end

function devicerequirements(config, info)
  layers = torel(:layer_name, ds.getin(config, [:device, :layers], []))
  supported_layers = ds.join(layers, ds.getin(info, [:device, :layers]))
  lcheck = checkavailability(layers, supported_layers, :layer_name, "layers")

  extensions = torel(:extension_name, ds.getin(config, [:device, :extensions], []))
  supported_extensions = ds.join(
    extensions, ds.getin(info, [:device, :extensions])
  )
  echeck = checkavailability(
    extensions, supported_extensions, :extension_name, "extensions"
  )

  devicefeatures = ds.getin(info, [:device, :features])
  features = ds.getin(config, [:device, :features])

  supported_features = ds.map(
    x -> [ds.key(x), featuressupported(ds.val(x), get(devicefeatures, ds.key(x)))],
    features
  )

  fcheck = checkfeatures(features, supported_features)

  queueinfo = queuerequirements(config, info)

  if !lcheck || !echeck || !fcheck
    return :device_unsuitable
  else
    info = ds.assoc(info, :queues, queueinfo)

    info = ds.update(info, :device, merge, ds.hashmap(
      :layers, supported_layers,
      :extensions, supported_extensions,
      :features, supported_features
    ))

    return info
  end
end

################################################################################
##### Resource creation
################################################################################

function extensions(config)
  ds.into!([], map(x -> get(x, :extension_name)), get(config, :extensions))
end

function layers(config)
  ds.into!([], map(x -> get(x, :layer_name)), get(config, :layers))
end

function instance(config)
  appinfo = vk.ApplicationInfo(
    ds.getin(config, [:app, :version]),
    ds.getin(config, [:engine, :version]),
    get(config, :version);
    application_name=ds.getin(config, [:app, :name]),
    engine_name=ds.getin(config, [:engine, :name])
  )

  vk.unwrap(vk.create_instance(
    layers(config),
    extensions(config);
    next=get(config, :debuginfo, C_NULL),
    application_info=appinfo
  ))
end

function choosedevice(devs)
  suitable = ds.remove(x -> ds.val(x) === :device_unsuitable, devs)
  @assert length(suitable) > 0 "No suitable GPUs found. Cannot continue."

  # FIXME: unlikely to be true in general
  best = first(suitable)

  return ds.key(best), ds.val(best)
end

function queuecreateinfos(spec)
  ds.into!(
    [],
    map(q -> vk.DeviceQueueCreateInfo(ds.key(q), repeat([1.0]; inner=ds.val(q)))),
    get(spec, :supported_counts)
  )
end

function device(pdev, info)
  dev = get(info, :device)
  features = get(dev, :features)

  dci = vk.DeviceCreateInfo(
    queuecreateinfos(get(info, :queues)),
    layers(dev),
    extensions(dev);
    enabled_features=vk.PhysicalDeviceFeatures(get(features, v"1.0")...),
    next=ds.reduce(
      (s, v) -> get(hw.featuretypes, v)(get(features, v)...; next=s),
      C_NULL,
      [v"1.3", v"1.2", v"1.1"]
    )
  )

  vk.unwrap(vk.create_device(pdev, dci))
end

################################################################################
##### Entrypoint
################################################################################

# REVIEW: Takes in a module which provides an OS window. The idea is to be able
# to swap glfw for sdl when required, but I need to standardise the api before
# that's realistic. I want the end user to be able to extend this library with
# their own windowing solution.
function setup(baseconfig, wm)
  windowconfig = wm.configure()

  devcfg = get(baseconfig, :dev_tooling, false) ? devtooling : ds.emptymap

  config = mergeconfig(defaults, devtooling, baseconfig, windowconfig)

  # The general flow is that you specify what you want in config, call a
  # negotiator which returns the best you can get, and if that's good enough,
  # you pass that info on to the creation fns.
  instinfo = instancerequirements(config)

  inst = instance(instinfo)

  debugmessenger = debug.debugmsgr(inst, get(instinfo, :debuginfo, nothing))

  window, resizecb = wm.window(get(config, :name), get(config, :window))

  surface = wm.surface(inst, window)

  pdevs = map(
    x -> [ds.key(x), devicerequirements(config, ds.val(x))],
    hw.physicaldevices(inst, surface)
  )

  pdev, deviceinfo = choosedevice(pdevs)

  dev = device(pdev, deviceinfo)

  system = ds.hashmap(
    :instance, inst,
    :window, window,
    # REVIEW: Include the windowmanager here? Or wrap the window object in a
    # struct that can query its size and whatnot?
    :surface, surface,
    :pdev, pdev,
    :device, dev
  )

  info = ds.assoc(deviceinfo, :instance, instinfo)

  return system, info, config
end

end # module
