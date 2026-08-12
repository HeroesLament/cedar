#version 410 core
struct GridUniformsData {
    vec4 line_color;
    vec4 background;
    vec2 spacing;
    float thickness;
};
struct GridUniformsBlock {
    GridUniformsData data;
};
struct VertexOutput {
    vec4 member;
    vec2 member_1;
};
vec2 v_texcoord_1 = vec2(0.0);

layout(std140) uniform GridUniforms { GridUniformsBlock u; };

vec4 output_ = vec4(0.0);

smooth in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

void function() {
    float phi_64_ = 0.0;
    float phi_95_ = 0.0;
    float phi_97_ = 0.0;
    bool phi_98_ = false;
    float phi_115_ = 0.0;
    float phi_129_ = 0.0;
    float phi_130_ = 0.0;
    float phi_131_ = 0.0;
    bool phi_132_ = false;
    float phi_142_ = 0.0;
    float phi_173_ = 0.0;
    float phi_175_ = 0.0;
    bool phi_176_ = false;
    float phi_193_ = 0.0;
    float phi_207_ = 0.0;
    float phi_208_ = 0.0;
    float phi_209_ = 0.0;
    bool phi_210_ = false;
    vec2 _e22 = v_texcoord_1;
    float _e28 = u.data.spacing[0u];
    float _e29 = (_e22.x / _e28);
    float _e33 = u.data.spacing[1u];
    float _e34 = (_e22.y / _e33);
    float _e35 = fwidth(_e29);
    float _e36 = fwidth(_e34);
    if ((_e35 < 0.0)) {
        phi_64_ = -(_e35);
    } else {
        phi_64_ = _e35;
    }
    float _e40 = phi_64_;
    float _e43 = u.data.thickness;
    if ((_e40 <= 0.0)) {
        phi_131_ = 0.0;
        phi_132_ = true;
    } else {
        bool _e45 = (_e43 <= 0.0);
        if (_e45) {
            phi_130_ = 0.0;
        } else {
            float _e46 = (_e29 - 0.5);
            float _e54 = float(((_e46 == _e46) ? ((_e46 > 2147483500.0) ? 2147483647 : ((_e46 < -2147483600.0) ? -2147483648 : int(_e46))) : 0));
            if ((_e46 < 0.0)) {
                bool _e56 = (_e54 != _e46);
                if (_e56) {
                    phi_95_ = (_e54 - 1.0);
                } else {
                    phi_95_ = 0.0;
                }
                float _e59 = phi_95_;
                phi_97_ = _e59;
                phi_98_ = (_e56 ? false : true);
            } else {
                phi_97_ = 0.0;
                phi_98_ = true;
            }
            float _e62 = phi_97_;
            bool _e64 = phi_98_;
            float _e66 = (_e46 - (_e64 ? _e54 : _e62));
            float _e68 = ((_e66 >= 1.0) ? 0.0 : _e66);
            float _e69 = (_e68 - 0.5);
            if ((_e69 < 0.0)) {
                phi_115_ = (0.5 - _e68);
            } else {
                phi_115_ = _e69;
            }
            float _e73 = phi_115_;
            float _e77 = (((_e43 * 0.5) - (_e73 / _e40)) + 0.5);
            if ((_e77 < 0.0)) {
                phi_129_ = 0.0;
            } else {
                phi_129_ = ((_e77 > 1.0) ? 1.0 : _e77);
            }
            float _e82 = phi_129_;
            phi_130_ = _e82;
        }
        float _e84 = phi_130_;
        phi_131_ = _e84;
        phi_132_ = _e45;
    }
    float _e86 = phi_131_;
    bool _e88 = phi_132_;
    float _e89 = (_e88 ? 0.0 : _e86);
    if ((_e36 < 0.0)) {
        phi_142_ = -(_e36);
    } else {
        phi_142_ = _e36;
    }
    float _e93 = phi_142_;
    if ((_e93 <= 0.0)) {
        phi_209_ = 0.0;
        phi_210_ = true;
    } else {
        bool _e95 = (_e43 <= 0.0);
        if (_e95) {
            phi_208_ = 0.0;
        } else {
            float _e96 = (_e34 - 0.5);
            float _e104 = float(((_e96 == _e96) ? ((_e96 > 2147483500.0) ? 2147483647 : ((_e96 < -2147483600.0) ? -2147483648 : int(_e96))) : 0));
            if ((_e96 < 0.0)) {
                bool _e106 = (_e104 != _e96);
                if (_e106) {
                    phi_173_ = (_e104 - 1.0);
                } else {
                    phi_173_ = 0.0;
                }
                float _e109 = phi_173_;
                phi_175_ = _e109;
                phi_176_ = (_e106 ? false : true);
            } else {
                phi_175_ = 0.0;
                phi_176_ = true;
            }
            float _e112 = phi_175_;
            bool _e114 = phi_176_;
            float _e116 = (_e96 - (_e114 ? _e104 : _e112));
            float _e118 = ((_e116 >= 1.0) ? 0.0 : _e116);
            float _e119 = (_e118 - 0.5);
            if ((_e119 < 0.0)) {
                phi_193_ = (0.5 - _e118);
            } else {
                phi_193_ = _e119;
            }
            float _e123 = phi_193_;
            float _e127 = (((_e43 * 0.5) - (_e123 / _e93)) + 0.5);
            if ((_e127 < 0.0)) {
                phi_207_ = 0.0;
            } else {
                phi_207_ = ((_e127 > 1.0) ? 1.0 : _e127);
            }
            float _e132 = phi_207_;
            phi_208_ = _e132;
        }
        float _e134 = phi_208_;
        phi_209_ = _e134;
        phi_210_ = _e95;
    }
    float _e136 = phi_209_;
    bool _e138 = phi_210_;
    float _e139 = (_e138 ? 0.0 : _e136);
    float _e141 = ((_e89 > _e139) ? _e89 : _e139);
    vec4 _e144 = u.data.background;
    vec4 _e147 = u.data.line_color;
    output_ = (_e144 + vec4(((_e147.x - _e144.x) * _e141), ((_e147.y - _e144.y) * _e141), ((_e147.z - _e144.z) * _e141), ((_e147.w - _e144.w) * _e141)));
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

