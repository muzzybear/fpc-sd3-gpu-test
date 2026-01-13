#version 460

layout (location=1) in vec2 uv;
layout (location=0) out vec4 color;

void main() {
    color = vec4(0.0, uv.x, uv.y, 1.0);
}
