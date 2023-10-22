#version 450

layout(binding = 0) uniform UniformBufferObject {
  mat4 model;
  mat4 view;
  mat4 projection;
} ubo;

layout(location = 0) in vec3 position;
layout(location = 1) in vec2 texCoord;

layout(location = 0) out vec3 fragColour;
layout(location = 1) out vec2 fragTexCoord;

void main() {
    // gl_PointSize = 50.0;
    gl_Position = ubo.projection * ubo.view * ubo.model * vec4(position, 1.0);
    fragColour = vec3(0.0,0.0,0.0);
    fragTexCoord = texCoord;
}
