#version 410 core
struct UniformsData {
    float row_offset;
    float domain_min;
    float domain_max;
};
struct UniformsBlock {
    UniformsData data;
};
struct VertexOutput {
    vec4 member;
    vec2 member_1;
};
vec2 v_texcoord_1 = vec2(0.0);

layout(std140) uniform Uniforms { UniformsBlock u; };

uniform sampler2D u_data;

uniform sampler2D u_colormap;

vec4 output_ = vec4(0.0);

smooth in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

void function() {
    float phi_86_ = 0.0;
    vec2 _e17 = v_texcoord_1;
    float _e22 = u.data.row_offset;
    float _e23 = (_e17.y + _e22);
    vec4 _e27 = texture(u_data, vec2(vec2(_e17.x, (_e23 - trunc(_e23)))));
    float _e31 = u.data.domain_min;
    float _e34 = u.data.domain_max;
    float _e35 = (_e34 - _e31);
    if ((_e35 == 0.0)) {
        phi_86_ = 0.0;
    } else {
        float _e38 = ((_e27.x - _e31) / _e35);
        float _e40 = ((_e38 < 0.0) ? 0.0 : _e38);
        phi_86_ = ((_e40 > 1.0) ? 1.0 : _e40);
    }
    float _e44 = phi_86_;
    vec4 _e46 = texture(u_colormap, vec2(vec2(_e44, 0.5)));
    output_ = vec4(_e46.x, _e46.y, _e46.z, 1.0);
    return;
}

void main() {
    vec2 v_texcoord = _vs2fs_location0;
    v_texcoord_1 = v_texcoord;
    function();
    vec4 _e3 = output_;
    _fs2p_location0 = _e3;
    return;
}

