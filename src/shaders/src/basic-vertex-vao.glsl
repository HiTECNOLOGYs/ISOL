#version 420

uniform mat4 view_m;

layout (location = 0) in vec2 vertex;
layout (location = 1) in vec2 uv;

out vec2 texcoord;

void main() {
  gl_Position = view_m * vec4(vertex, 0.0, 1.0);
  texcoord = uv;
}
