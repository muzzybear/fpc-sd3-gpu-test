#version 460

layout(set = 1, binding = 0) uniform Transform {
    mat4 MVPMatrix;
};

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inColor;
layout(location = 2) in vec2 inUV;

layout(location = 0) out vec3 color;
layout(location = 1) out vec2 uv;

void main() {
    gl_Position = MVPMatrix * vec4(inPosition, 1);
    color = inColor;
    uv = inUV;
}
