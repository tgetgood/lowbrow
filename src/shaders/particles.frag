#version 450

layout(location = 0) in vec4 fragColour;

layout(location = 0) out vec4 outColour;

void main() {
  vec2 pc = 2.0 * gl_PointCoord - 1.0;

  if (dot(pc, pc) > 1.0) {
    discard;
  }
  outColour = fragColour;
}
