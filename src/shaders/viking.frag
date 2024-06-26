#version 450

layout(binding = 1) uniform sampler2D sam;

layout(location = 0) in vec3 fragColour;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec4 outColour;

void main() {
  outColour = vec4(texture(sam, texCoord).rgb, 1.0);
}
