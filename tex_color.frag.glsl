#version 460

layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;
layout(set = 2, binding = 0) uniform sampler2D tex;

layout(location = 0) out vec4 outColor;

void main() {
    vec4 texcolor = texture(tex, uv);
    outColor = texcolor * color;
}
