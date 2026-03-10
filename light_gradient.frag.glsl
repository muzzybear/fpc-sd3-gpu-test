#version 460

layout(location = 1) in vec2 uv;
layout(location = 0) out vec4 color;

void main() {
    float d = length(0.5 - uv) / 0.5;
    color = mix(vec4(1.0), vec4(0.0), d);
}
