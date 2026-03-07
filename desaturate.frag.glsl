#version 460

layout(location = 0) in vec4 color;
layout(location = 1) in vec2 uv;
layout(set = 2, binding = 0) uniform sampler2D tex;
layout(set = 3, binding = 0) uniform Params {
    float desaturate;
};

layout(location = 0) out vec4 outColor;

void main() {
    vec4 texcolor = texture(tex, uv);
    vec4 gray = vec4(dot(vec4(0.2126, 0.7152, 0.0722, 1), texcolor));
    outColor = mix(texcolor, gray, desaturate) * color;
}
