#version 450

layout(location = 0) in vec2 position;
layout(location = 1) in vec4 colour;

layout(location = 0) out vec4 fragColour;

void main() {
    gl_PointSize = 2.0;
    gl_Position = vec4(position, 0.5, 1.0);
    fragColour = colour;
}
