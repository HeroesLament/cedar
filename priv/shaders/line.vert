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

vec2 a_position_1 = vec2(0.0);

vec2 a_neighbor_1 = vec2(0.0);

float a_side_1 = 0.0;

vec4 out_position = vec4(0.0, 0.0, 0.0, 1.0);

layout(location = 0) in vec2 _p2vs_location0;
layout(location = 1) in vec2 _p2vs_location1;
layout(location = 2) in float _p2vs_location2;

void function_1() {
    float phi_70_ = 0.0;
    float phi_76_ = 0.0;
    float phi_86_ = 0.0;
    float phi_92_ = 0.0;
    float phi_93_ = 0.0;
    int phi_109_ = 0;
    float phi_112_ = 0.0;
    int phi_128_ = 0;
    int phi_110_ = 0;
    float phi_113_ = 0.0;
    bool phi_130_ = false;
    float phi_135_ = 0.0;
    type_13 phi_140_ = type_13(0.0, 0.0);
    float local = 0.0;
    vec2 _e21 = a_position_1;
    vec2 _e22 = a_neighbor_1;
    float _e23 = a_side_1;
    float _e33 = u.data.viewport[0u];
    float _e34 = ((_e22.x - _e21.x) * _e33);
    float _e38 = u.data.viewport[1u];
    float _e39 = ((_e22.y - _e21.y) * _e38);
    bool _e40 = (_e34 < 0.0);
    if (_e40) {
        phi_70_ = -(_e34);
    } else {
        phi_70_ = _e34;
    }
    float _e43 = phi_70_;
    bool _e44 = (_e39 < 0.0);
    if (_e44) {
        phi_76_ = -(_e39);
    } else {
        phi_76_ = _e39;
    }
    float _e47 = phi_76_;
    if ((_e43 > _e47)) {
        if (_e40) {
            phi_86_ = -(_e34);
        } else {
            phi_86_ = _e34;
        }
        float _e51 = phi_86_;
        phi_93_ = _e51;
    } else {
        if (_e44) {
            phi_92_ = -(_e39);
        } else {
            phi_92_ = _e39;
        }
        float _e54 = phi_92_;
        phi_93_ = _e54;
    }
    float _e56 = phi_93_;
    if ((_e56 <= 0.0)) {
        phi_140_ = type_13(0.0, 0.0);
    } else {
        float _e58 = (_e34 / _e56);
        float _e59 = (_e39 / _e56);
        float _e62 = ((_e58 * _e58) + (_e59 * _e59));
        if ((_e62 <= 0.0)) {
            phi_135_ = 0.0;
        } else {
            phi_109_ = 0;
            phi_112_ = _e62;
            bool loop_init = true;
            while(true) {
                if (!loop_init) {
                    phi_109_ = phi_110_;
                    phi_112_ = phi_113_;
                    if (!(phi_130_)) {
                        break;
                    }
                }
                loop_init = false;
                int _e65 = phi_109_;
                float _e67 = phi_112_;
                local = _e67;
                if ((_e65 < 20)) {
                    float _e71 = (0.5 * (_e67 + (_e62 / _e67)));
                    bool _e72 = (_e71 == _e67);
                    if (_e72) {
                        phi_128_ = 0;
                    } else {
                        phi_128_ = (_e65 + 1);
                    }
                    int _e75 = phi_128_;
                    phi_110_ = _e75;
                    phi_113_ = _e71;
                    phi_130_ = (_e72 ? false : true);
                } else {
                    phi_110_ = 0;
                    phi_113_ = 0.0;
                    phi_130_ = false;
                }
                int _e78 = phi_110_;
                float _e80 = phi_113_;
                bool _e82 = phi_130_;
                continue;
            }
            float _e123 = local;
            phi_135_ = _e123;
        }
        float _e85 = phi_135_;
        float _e86 = (1.0 / _e85);
        phi_140_ = type_13((_e58 * _e86), (_e59 * _e86));
    }
    type_13 _e91 = phi_140_;
    float _e97 = u.data.line_width;
    float _e98 = (_e97 * 0.5);
    out_position = vec4((_e21.x + ((((-(_e91.member_1) * _e98) * 2.0) / _e33) * _e23)), (_e21.y + ((((_e91.member * _e98) * 2.0) / _e38) * _e23)), 0.0, 1.0);
    return;
}

void main() {
    vec2 a_position = _p2vs_location0;
    vec2 a_neighbor = _p2vs_location1;
    float a_side = _p2vs_location2;
    a_position_1 = a_position;
    a_neighbor_1 = a_neighbor;
    a_side_1 = a_side;
    function_1();
    float _e8 = out_position.y;
    out_position.y = -(_e8);
    vec4 _e10 = out_position;
    gl_Position = _e10;
    gl_Position.yz = vec2(-gl_Position.y, gl_Position.z * 2.0 - gl_Position.w);
    return;
}

