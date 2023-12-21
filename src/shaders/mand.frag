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

  uint i = uint(texCoord.x * (pcs.window[0] - 1));
  uint j = uint(texCoord.y * (pcs.window[1] - 1));

  uint n = i + j * pcs.window[0];

  Pixel p = pixels[n];

  int c = pixels[n].count;

  float r = float(c>>8)/15.0;
  float g = float((c&((1<<8)-1))>>4)/15.0;
  float b = float(c&15)/15.0;

  // outColour = vec4(0.0, 0.0, float(c/pcs.count), 1.0);
  outColour = vec4(r,g,b, 1.0);
}
