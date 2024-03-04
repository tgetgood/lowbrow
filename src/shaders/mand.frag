#version 450

struct Pixel {
  uint done;
  uint count;
  vec2 mu;
  vec2 z;
};

// layout(binding = 0) uniform sampler2D sam;

layout(push_constant) uniform constants {
  uvec2 window;
  uint count;
} pcs;

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColour;

layout(std140, binding = 0) readonly restrict buffer PixelSSBOIn {
   Pixel pixels[ ];
};

void main() {
  // outColour = vec4(texture(sam, texCoord).rgb, 1.0);
  // outColour = vec4(texCoord, 1.0, 1.0);
  uint i = uint(round(texCoord.x * float(pcs.window[0] - 1)));
  uint j = uint(round(texCoord.y * float(pcs.window[1] - 1)));

  // if (i < j) {
  //   discard;
  // }

  uint n = i + j * pcs.window[0];
  uint N = pcs.window[0] * pcs.window[1];

  if (n >= N) {
    discard;
  } else {
    Pixel p = pixels[n];
  
    uint c = pixels[n].count;

    // if (c < 100000) {
    //   discard;
    // }

    // float r = float(c>>8)/15.0;
    // float g = float((c&((1<<8)-1))>>4)/15.0;
    // float b = float(c&15)/15.0;

    // outColour = vec4(pixels[n].mu, 0.0, 1.0);
    outColour = vec4(p.mu, float(c)/float(pcs.count) + 0.1, 1.0);
    // outColour = vec4(r,g,b, 1.0);
  }
}
