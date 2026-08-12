#version 410 core
struct LineUniformsData {
    vec4 color;
    vec2 viewport;
    float line_width;
};
struct LineUniformsBlock {
    LineUniformsData data;
};
struct type_13 {
    float member;
    float member_1;
};
layout(std140) uniform LineUniforms { LineUniformsBlock u; };

vec4 output_ = vec4(0.0);

layout(location = 0) out vec4 _fs2p_location0;

void function() {
    vec4 _e23 = u.data.color;
    output_ = _e23;
    return;
}

void main() {
    function();
    vec4 _e1 = output_;
    _fs2p_location0 = _e1;
    return;
}

