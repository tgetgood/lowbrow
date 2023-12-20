#version 450

struct Pixel {
  bool done;
  int count;
  vec2 mu;
  vec2 z;
};

// layout(binding = 1) uniform sampler2D sam;

layout(push_constant) uniform constants {
  uvec2 window;
  int count;
} pcs;

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColour;

layout(std140, binding = 0) readonly restrict buffer PixelSSBOIn {
   Pixel pixels[ ];
};

void main() {
  // outColour = vec4(texture(sam, texCoord * 1.0).rgb, 1.0);
  // outColour = vec4(texCoord, 1.0, 1.0);

  uint i = uint((texCoord.x + 1) * pcs.window[0]/2);
  uint j = uint((texCoord.y + 1) * pcs.window[1]/2);

  uint n = i + j * pcs.window[0];

  int c = pixels[n].count;

  outColour = vec4(float(c)/float(pcs.count), 0.0, 0.0, 1.0);
}
