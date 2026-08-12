#version 410 core
struct type_5 {
    vec4 member;
    vec4 member_1;
    vec4 member_2;
    vec4 member_3;
};
struct type_6 {
    vec3 member;
    vec3 member_1;
    vec3 member_2;
};
struct MeshUniformsData {
    type_5 mvp;
    type_6 normal_matrix;
    vec3 light_direction;
    vec4 base_color;
};
struct MeshUniformsBlock {
    MeshUniformsData data;
};
struct type_12 {
    float member;
    float member_1;
    float member_2;
};
struct VertexOutput {
    vec4 member;
    vec3 member_1;
};
vec3 v_normal_1 = vec3(0.0);

layout(std140) uniform MeshUniforms { MeshUniformsBlock u; };

vec4 output_ = vec4(0.0);

smooth in vec3 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

void function() {
    float phi_59_ = 0.0;
    float phi_65_ = 0.0;
    float phi_71_ = 0.0;
    int phi_100_ = 0;
    float phi_103_ = 0.0;
    int phi_119_ = 0;
    int phi_101_ = 0;
    float phi_104_ = 0.0;
    bool phi_121_ = false;
    float phi_126_ = 0.0;
    type_12 phi_132_ = type_12(0.0, 0.0, 0.0);
    float phi_165_ = 0.0;
    float local = 0.0;
    vec3 _e24 = v_normal_1;
    if ((_e24.x < 0.0)) {
        phi_59_ = -(_e24.x);
    } else {
        phi_59_ = _e24.x;
    }
    float _e31 = phi_59_;
    if ((_e24.y < 0.0)) {
        phi_65_ = -(_e24.y);
    } else {
        phi_65_ = _e24.y;
    }
    float _e35 = phi_65_;
    if ((_e24.z < 0.0)) {
        phi_71_ = -(_e24.z);
    } else {
        phi_71_ = _e24.z;
    }
    float _e39 = phi_71_;
    float _e41 = ((_e31 > _e35) ? _e31 : _e35);
    float _e43 = ((_e41 > _e39) ? _e41 : _e39);
    if ((_e43 <= 0.0)) {
        phi_132_ = type_12(0.0, 0.0, 0.0);
    } else {
        float _e45 = (_e24.x / _e43);
        float _e46 = (_e24.y / _e43);
        float _e47 = (_e24.z / _e43);
        float _e52 = (((_e45 * _e45) + (_e46 * _e46)) + (_e47 * _e47));
        if ((_e52 <= 0.0)) {
            phi_126_ = 0.0;
        } else {
            phi_100_ = 0;
            phi_103_ = _e52;
            bool loop_init = true;
            while(true) {
                if (!loop_init) {
                    phi_100_ = phi_101_;
                    phi_103_ = phi_104_;
                    if (!(phi_121_)) {
                        break;
                    }
                }
                loop_init = false;
                int _e55 = phi_100_;
                float _e57 = phi_103_;
                local = _e57;
                if ((_e55 < 20)) {
                    float _e61 = (0.5 * (_e57 + (_e52 / _e57)));
                    bool _e62 = (_e61 == _e57);
                    if (_e62) {
                        phi_119_ = 0;
                    } else {
                        phi_119_ = (_e55 + 1);
                    }
                    int _e65 = phi_119_;
                    phi_101_ = _e65;
                    phi_104_ = _e61;
                    phi_121_ = (_e62 ? false : true);
                } else {
                    phi_101_ = 0;
                    phi_104_ = 0.0;
                    phi_121_ = false;
                }
                int _e68 = phi_101_;
                float _e70 = phi_104_;
                bool _e72 = phi_121_;
                continue;
            }
            float _e135 = local;
            phi_126_ = _e135;
        }
        float _e75 = phi_126_;
        float _e76 = (1.0 / _e75);
        phi_132_ = type_12((_e45 * _e76), (_e46 * _e76), (_e47 * _e76));
    }
    type_12 _e82 = phi_132_;
    vec3 _e88 = u.data.light_direction;
    float _e96 = (((_e82.member * _e88.x) + (_e82.member_1 * _e88.y)) + (_e82.member_2 * _e88.z));
    if ((_e96 < 0.0)) {
        phi_165_ = 0.0;
    } else {
        phi_165_ = ((_e96 > 1.0) ? 1.0 : _e96);
    }
    float _e101 = phi_165_;
    float _e103 = (0.15 + (0.85 * _e101));
    float _e107 = u.data.base_color[0u];
    float _e112 = u.data.base_color[1u];
    float _e117 = u.data.base_color[2u];
    float _e122 = u.data.base_color[3u];
    output_ = vec4((_e107 * _e103), (_e112 * _e103), (_e117 * _e103), _e122);
    return;
}

void main() {
    vec3 v_normal = _vs2fs_location0;
    v_normal_1 = v_normal;
    function();
    vec4 _e3 = output_;
    _fs2p_location0 = _e3;
    return;
}

