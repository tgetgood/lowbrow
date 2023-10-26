#version 450

layout(binding = 1) uniform StorageBuffer {
  vec2 position;
  vec4 colour;
} particle;

layout(location = 0) out vec4 fragColour;

void main() {
    gl_PointSize = 50.0;
    gl_Position = vec3(particle.position, 1.0);
    fragColour = particle.colour;
}
