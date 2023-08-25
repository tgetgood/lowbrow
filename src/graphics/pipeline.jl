module pipeline

import window
import hardware as hw
import Vulkan as vk
import DataStructures: getin, emptymap, hashmap, emptyvector, into

function glslc(src, out)
  run(`glslc $(@__DIR__)/../../shaders/$src -o $out`)
end

function compileshader(system, fname)
  (tmp, io) = mktemp()
  close(io)
  glslc(fname, tmp)
  bin = read(tmp)
  size = length(bin)
  code = reinterpret(UInt32, bin)
  vk.unwrap(vk.create_shader_module(get(system, :device), size, code))
end

function shaders(config, system)
  vert = vk.PipelineShaderStageCreateInfo(
    vk.SHADER_STAGE_VERTEX_BIT,
    compileshader(system, getin(config, [:shaders, :vert])),
    "main"
  )

  frag = vk.PipelineShaderStageCreateInfo(
    vk.SHADER_STAGE_FRAGMENT_BIT,
    compileshader(system, getin(config, [:shaders, :frag])),
    "main"
  )

  [vert, frag]
end

function renderpass(config, system)
  hashmap(
    :renderpass,
    vk.unwrap(vk.create_render_pass(
      get(system, :device),
      [vk.AttachmentDescription(
        getin(config, [:swapchain, :format]),
        vk.SAMPLE_COUNT_1_BIT,
        vk.ATTACHMENT_LOAD_OP_CLEAR,
        vk.ATTACHMENT_STORE_OP_STORE,
        vk.ATTACHMENT_LOAD_OP_DONT_CARE,
        vk.ATTACHMENT_STORE_OP_DONT_CARE,
        vk.IMAGE_LAYOUT_UNDEFINED,
        vk.IMAGE_LAYOUT_PRESENT_SRC_KHR
      )],
      [vk.SubpassDescription(
        vk.PIPELINE_BIND_POINT_GRAPHICS,
        [],
        [vk.AttachmentReference(0, vk.IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL)],
        []
      )],
      [vk.SubpassDependency(
        vk.SUBPASS_EXTERNAL,
        0;
        src_stage_mask=vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        src_access_mask=0,
        dst_stage_mask=vk.PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        dst_access_mask=vk.ACCESS_COLOR_ATTACHMENT_WRITE_BIT
      )]
    ))
  )
end

function createpipelines(config, system)
  dynamic_state = vk.PipelineDynamicStateCreateInfo([
    vk.DYNAMIC_STATE_SCISSOR,
    vk.DYNAMIC_STATE_VIEWPORT
  ])

  input_assembly_state = vk.PipelineInputAssemblyStateCreateInfo(
    vk.PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
    false
  )

  win = window.size(get(system, :window))

  viewports = [vk.Viewport(0, 0, win.width, win.height, 0, 1)]
  scissors = [vk.Rect2D(vk.Offset2D(0, 0), get(system, :extent))]

  viewport_state = vk.PipelineViewportStateCreateInfo(
    ;
    viewports, scissors
  )

  multisample_state = vk.PipelineMultisampleStateCreateInfo(
    vk.SAMPLE_COUNT_1_BIT,
    false,
    1,
    false,
    false
  )

  color_write_mask = vk.COLOR_COMPONENT_R_BIT |
    vk.COLOR_COMPONENT_G_BIT |
    vk.COLOR_COMPONENT_B_BIT |
    vk.COLOR_COMPONENT_A_BIT

  color_blend_state = vk.PipelineColorBlendStateCreateInfo(
    false,
    vk.LOGIC_OP_COPY,
    [vk.PipelineColorBlendAttachmentState(
      false,
      vk.BLEND_FACTOR_ONE,
      vk.BLEND_FACTOR_ZERO,
      vk.BLEND_OP_ADD,
      vk.BLEND_FACTOR_ONE,
      vk.BLEND_FACTOR_ZERO,
      vk.BLEND_OP_ADD;
      color_write_mask
    )],
    NTuple{4, Float32}((0,0,0,0))
  )

  layout = vk.unwrap(vk.create_pipeline_layout(get(system, :device), [], []))

  ps = vk.unwrap(vk.create_graphics_pipelines(
    get(system, :device),
    [vk.GraphicsPipelineCreateInfo(
      shaders(config, system),
      vk.PipelineRasterizationStateCreateInfo(
        false,
        false,
        vk.POLYGON_MODE_FILL,
        vk.FRONT_FACE_CLOCKWISE,
        false,
        0.0, 0.0, 0.0,
        1.0;
        cull_mode=vk.CULL_MODE_BACK_BIT
      ),
      layout,
      0,
      -1;
      vertex_input_state=vk.PipelineVertexInputStateCreateInfo([], []),
      input_assembly_state,
      viewport_state,
      multisample_state,
      color_blend_state,
      dynamic_state,
      render_pass=get(system, :renderpass)
    )]
  ))

  hashmap(:pipeline, ps[1][1], :viewports, viewports, :scissors, scissors)
end

function createframebuffers(config, system)
  dev = get(system, :device)
  images = get(system, :imageviews)
  pass = get(system, :renderpass)
  extent = get(system, :extent)

  hashmap(
    :framebuffers,
    into(
      emptyvector,
      map(image -> vk.create_framebuffer(
        dev,
        pass,
        [image],
        extent.width,
        extent.height,
        1
      )) ∘
      map(vk.unwrap),
      images
    )
  )
end

end
