#version 450

// layout(binding = 1) uniform sampler2D sam;

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 outColour;

int exceeds(const float mr, const float mi) {
  float z_real = 0.0;
  float z_im = 0.0;

  for (int i = 0; i < (1<<12); i++) {
    if (z_real > 10 || z_real < -10 || z_im > 10 || z_im < -10) {
      return i;
    }
    float zr = z_real;
    float zi = z_im;
    
    z_real = zr*zr - zi*zi - mr;
    z_im = 2*zr*zi - mi;
  }
  return (1<<12)-1;
}

void main() {
  // outColour = vec4(texture(sam, texCoord * 1.0).rgb, 1.0);
  // outColour = vec4(texCoord, 1.0, 1.0);

  const float mu_real = texCoord.x * 2;
  const float mu_im = texCoord.y * -2;

  int c = exceeds(mu_real, mu_im);
  
  float r = float(c>>8)/15.0;
  float g = float((c&((1<<8) - 1))>>4)/15.0;
  float b = float(c&15)/15.0;

  outColour = vec4(r, g, b, 1.0);
}
