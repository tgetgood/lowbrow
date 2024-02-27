module init

import Vulkan as vk
import DataStructures as ds
import TaskPipelines as tp

import debug
import resources as rd
import hardware as hw

import pprint
import Overrides

################################################################################
##### Default app config
################################################################################

VS = Union{Vector, ds.Vector}

mergeconfig(x, y) = y
mergeconfig(x::ds.Map, y::ds.Map) = ds.mergewith(mergeconfig, x, y)
mergeconfig(x::VS, y::VS) = ds.into(y, x)
mergeconfig() = ds.emptymap
mergeconfig(x) = x
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
      # On modern hardware, 4x msaa has very little cost, so this seems like a
      # good default. Defaulting to 1 will just make things look bad.
      :samples, 4,
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
    :engine, config.engine
  )

  info = hw.instanceinfo()
  ic = config.instance
  api_version = ic.vulkan_version

  layers = torel(:layer_name, get(ic, :layers, []))
  extensions = torel(:extension_name, get(ic, :extensions, []))

  supported_layers = ds.join(layers, info.layers)
  supported_extensions = ds.join(extensions, info.extensions)

  checkavailability(layers, supported_layers, :layer_name, "layers")

  checkavailability(
    extensions, supported_extensions, :extension_name, "extensions"
  )

  version = info.version

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

function allocatequeues(requested_counts, supported_counts, pipelines, qfs)
  if requested_counts == supported_counts
    pbyf = ds.mapvals(ds.keys, pipelines)
    ds.into(
      ds.emptymap,
      ds.mapvals(v -> reduce(ds.concat, map(x -> get(pbyf, x), v)))
      ∘
      ds.remove(e -> ds.emptyp(ds.val(e)))
      ∘
      ds.map(e -> ds.mapindexed(
        (i, name) -> [name, vk.DeviceQueueInfo2(ds.key(e), i - 1)],
        ds.val(e))
      )
      ∘
      ds.cat(),
      ds.invert(qfs)
    )
  elseif sum(ds.vals(supported_counts)) == 1
    # REVIEW: If the hardware only supports one queue, it *has to be* (0, 0), no?
    q = tp.SharedQueueInfo(vk.DeviceQueueInfo2(0, 0))
    reduce(merge, map(m -> ds.mapvals(_ -> q, m), ds.vals(pipelines)))
  else
    # Hard case. Also the most likely, I would think.
    throw("not implemented")
  end
end

function queuerequirements(config, info)
  qfp = info.device.qf_properties
  qtypes = [:transfer, :compute, :graphics]

  queue_families = ds.into(ds.emptymap, map(x -> hw.queuetype(qfp, x)), qtypes)

  pipelines = ds.groupby(x -> ds.val(x).type, config.pipelines)

  pipelinecounts = ds.mapvals(ds.count, pipelines)

  queuecountbyfamily = ds.into(
    ds.emptymap,
    ds.mapvals(x -> sum(ds.into!([], map(y -> get(pipelinecounts, y, 0)), x)))
    ∘
    filter(e -> ds.val(e) > 0),
    ds.invert(queue_families)
  )

  if !get(config, :headless, false)
    queue_families = ds.assoc(
      queue_families,
      :presentation,
      first(sort(ds.seq(info.surface.presentation_qfs)))
    )

    presqf = queue_families.presentation

    queuecountbyfamily = ds.assoc(
      queuecountbyfamily,
      presqf,
      get(queuecountbyfamily, presqf, 0) + 1
    )

    pipelines = ds.assoc(pipelines, :presentation,
      ds.hashmap(:presentation, ds.hashmap(:type, :presentation))
    )
  end

  supported_counts = ds.into(
    ds.emptymap,
    map(x -> [ds.key(x), min(ds.val(x), qfp[ds.key(x) + 1].queue_count)])
    ∘
    filter(x -> x[2] > 0),
    queuecountbyfamily
  )

  queue_allocations = allocatequeues(
    queuecountbyfamily, supported_counts, pipelines, queue_families
  )

  ds.hashmap(
    :queue_families, queue_families,
    :supported_counts, supported_counts,
    :allocations, queue_allocations
  )
end

function checkswapchain(requested, supported)
  true
end

function swapchainrequirements(config, info)
  # TODO: check and negotiate.
  config.swapchain
end

function devicerequirements(config, info)
  layers = torel(:layer_name, ds.getin(config, [:device, :layers], []))
  supported_layers = ds.join(layers, info.device.layers)
  lcheck = checkavailability(layers, supported_layers, :layer_name, "layers")

  extensions = torel(:extension_name, ds.getin(config, [:device, :extensions], []))
  supported_extensions = ds.join(extensions, info.device.extensions)
  echeck = checkavailability(
    extensions, supported_extensions, :extension_name, "extensions"
  )

  devicefeatures = info.device.features
  features = config.device.features

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

    if !get(config, :headless, false)
      swapchaininfo = swapchainrequirements(config, info)

      if !checkswapchain(config.swapchain, swapchaininfo)
        return :device_unsuitable
      end

      info = ds.assoc(info, :swapchain, swapchaininfo)

    end

    return info
  end
end

################################################################################
##### Resource creation
################################################################################

function extensions(config)
  ds.into!([], map(x -> x.extension_name), config.extensions)
end

function layers(config)
  ds.into!([], map(x -> x.layer_name), config.layers)
end

function instance(config)
  appinfo = vk.ApplicationInfo(
    config.app.version,
    config.engine.version,
    config.version;
    application_name=config.app.name,
    engine_name=config.engine.name
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
    map(q -> (ds.key(q), repeat([1.0]; inner=ds.val(q))))
    ∘
    filter(t -> length(t[2]) > 0)
    ∘
    map(t -> vk.DeviceQueueCreateInfo(t...)),
    spec.supported_counts
  )
end

function device(pdev, info)
  dev = info.device
  features = dev.features

  dci = vk.DeviceCreateInfo(
    queuecreateinfos(info.queues),
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

const emptycachestate = ds.hashmap(
  :queues, ds.emptymap
)

function emptycache()
  ds.Atom(emptycachestate)
end

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

  window, resizecb = wm.window(config.name, config.window)

  surface = wm.surface(inst, window)

  pdevs = map(
    x -> [ds.key(x), devicerequirements(config, ds.val(x))],
    hw.physicaldevices(inst, surface)
  )

  pdev, deviceinfo = choosedevice(pdevs)

  dev = device(pdev, deviceinfo)

  info = ds.assoc(deviceinfo, :instance, instinfo)

  cache = emptycache()

  system = ds.hashmap(
    :spec, info,
    # REVIEW: There's a lot of caching going on but if I want to be able to
    # switch projects or reload a project without killing the process and
    # reloading from scratch, the caches must be local.
    #
    # Nonetheless, I don't like this idea of carrying mutable state around...
    :cache, cache,
    :instance, inst,
    :window, window,
    # REVIEW: Include the windowmanager here? Or wrap the window object in a
    # struct that can query its size and whatnot?
    :surface, surface,
    :pdev, pdev,
    :device, dev
  )

  return system, config
end

end # module
