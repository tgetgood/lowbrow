module graphics

import hardware as hw
import init
import pipeline as gp
import render as draw
import debug
import Glfw as window
import framework as fw

import Vulkan as vk
import DataStructures as ds
import DataStructures: hashmap, emptymap


function configure(prog)
  config = mergeconfig(defaults, prog)

  if get(config, :dev_tools, false)
    config = mergeconfig(config, devtooling)
  end

  mergeconfig(config, window.configure())
end

function staticinit(config)
  steps = [
    init.instance,
    debug.debugmsgr,
    window.createwindow,
    window.createsurface,

    # REVIEW: Decide which kinds of queues we're going to need before we create
    # the device, or just create all of the queues I might need and a command
    # pool for each? Right now the latter is simpler, but it might not be a good
    # choice.
    # However, if we start with an empty command pool and allocate on demand,
    # then the current strategy of figuring out what pool to use for everything
    # up front is fine.
    hw.createdevice,

    # This ^ is the core setup.
    #
    # We need to break the config up logically so that we perform 3
    # rounds of negotiations.
    # 1. Negotiate the instance, AKA choose the best API version and
    # extensions that are available. And make sure we can open a window and
    # create a render surface.
    # 2. Negotiate (and possibly choose) the physical and logical devices based
    # on the desired and available extentions. Then choose the best config
    # available.

    hw.createcommandpools,
  ]

  ds.reduce((s, f) -> begin @info f; merge(s, f(s, config)) end, emptymap, steps)
end

end # module
