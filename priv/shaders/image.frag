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
    float phi_79_ = 0.0;
    float phi_81_ = 0.0;
    bool phi_82_ = false;
    float phi_120_ = 0.0;
    float phi_121_ = 0.0;
    vec2 _e25 = v_texcoord_1;
    float _e30 = u.data.row_offset;
    float _e31 = (_e25.y + _e30);
    float _e39 = float(((_e31 == _e31) ? ((_e31 > 2147483500.0) ? 2147483647 : ((_e31 < -2147483600.0) ? -2147483648 : int(_e31))) : 0));
    if ((_e31 < 0.0)) {
        bool _e41 = (_e39 != _e31);
        if (_e41) {
            phi_79_ = (_e39 - 1.0);
        } else {
            phi_79_ = 0.0;
        }
        float _e44 = phi_79_;
        phi_81_ = _e44;
        phi_82_ = (_e41 ? false : true);
    } else {
        phi_81_ = 0.0;
        phi_82_ = true;
    }
    float _e47 = phi_81_;
    bool _e49 = phi_82_;
    float _e51 = (_e31 - (_e49 ? _e39 : _e47));
    vec4 _e55 = texture(u_data, vec2(vec2(_e25.x, ((_e51 >= 1.0) ? 0.0 : _e51))));
    float _e59 = u.data.domain_min;
    float _e62 = u.data.domain_max;
    float _e63 = (_e62 - _e59);
    if ((_e63 == 0.0)) {
        phi_121_ = 0.0;
    } else {
        float _e66 = ((_e55.x - _e59) / _e63);
        if ((_e66 < 0.0)) {
            phi_120_ = 0.0;
        } else {
            phi_120_ = ((_e66 > 1.0) ? 1.0 : _e66);
        }
        float _e71 = phi_120_;
        phi_121_ = _e71;
    }
    float _e73 = phi_121_;
    vec4 _e75 = texture(u_colormap, vec2(vec2(_e73, 0.5)));
    output_ = vec4(_e75.x, _e75.y, _e75.z, 1.0);
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

