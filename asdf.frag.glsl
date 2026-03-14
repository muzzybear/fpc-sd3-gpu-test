#version 460

layout(location = 0) in vec3 color;
layout(location = 0) out vec4 outColor;

// TODO uniforms: resolution, viewpos, viewdir
// TODO SSBO or storage texture for map data

void main() {
    vec2 resolution = vec2(640, 480);
    vec2 screenpos = 2.0 * gl_FragCoord.xy / resolution - 1.0;

    float viewangle = 0.5;
    float s = sin(viewangle);
    float c = cos(viewangle);

    vec3 raydir = normalize(vec3(screenpos.x, -screenpos.y, 1.0)); // -45 to +45 degrees
    raydir.xz = mat2(c, -s, s, c) * raydir.xz;
    vec3 ground = vec3(0.0, -2.0, 0.0);
    float dy = dot(raydir, ground);
    vec2 hit = raydir.xz / dy;
    float dist = length(hit);

    vec2 uv = mod(hit, 1.0);
    vec2 rr = abs(uv - 0.5) * 2.0;
    float r = min(rr.x, rr.y);

    vec3 c1 = vec3(0.0, 0.0, 0.0);
    vec3 c2 = vec3(0.5, 0.8, 0.8);
    vec3 color = mix(c1, c2, smoothstep(0.05, 0.1, r));
    outColor = vec4(color / dist, 1.0);
}
