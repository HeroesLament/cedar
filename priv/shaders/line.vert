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
    int phi_78_ = 0;
    float phi_81_ = 0.0;
    int phi_97_ = 0;
    int phi_79_ = 0;
    float phi_82_ = 0.0;
    bool phi_99_ = false;
    float phi_104_ = 0.0;
    type_13 phi_109_ = type_13(0.0, 0.0);
    float local = 0.0;
    vec2 _e21 = a_position_1;
    vec2 _e22 = a_neighbor_1;
    float _e23 = a_side_1;
    float _e33 = u.data.viewport[0u];
    float _e34 = ((_e22.x - _e21.x) * _e33);
    float _e38 = u.data.viewport[1u];
    float _e39 = ((_e22.y - _e21.y) * _e38);
    float _e42 = ((_e34 * _e34) + (_e39 * _e39));
    bool _e43 = (_e42 <= 0.0);
    if (_e43) {
        phi_109_ = type_13(0.0, 0.0);
    } else {
        if (_e43) {
            phi_104_ = 0.0;
        } else {
            phi_78_ = 0;
            phi_81_ = _e42;
            bool loop_init = true;
            while(true) {
                if (!loop_init) {
                    phi_78_ = phi_79_;
                    phi_81_ = phi_82_;
                    if (!(phi_99_)) {
                        break;
                    }
                }
                loop_init = false;
                int _e45 = phi_78_;
                float _e47 = phi_81_;
                local = _e47;
                if ((_e45 < 20)) {
                    float _e51 = (0.5 * (_e47 + (_e42 / _e47)));
                    bool _e52 = (_e51 == _e47);
                    if (_e52) {
                        phi_97_ = 0;
                    } else {
                        phi_97_ = (_e45 + 1);
                    }
                    int _e55 = phi_97_;
                    phi_79_ = _e55;
                    phi_82_ = _e51;
                    phi_99_ = (_e52 ? false : true);
                } else {
                    phi_79_ = 0;
                    phi_82_ = 0.0;
                    phi_99_ = false;
                }
                int _e58 = phi_79_;
                float _e60 = phi_82_;
                bool _e62 = phi_99_;
                continue;
            }
            float _e98 = local;
            phi_104_ = _e98;
        }
        float _e65 = phi_104_;
        float _e66 = (1.0 / _e65);
        phi_109_ = type_13((_e34 * _e66), (_e39 * _e66));
    }
    type_13 _e71 = phi_109_;
    float _e77 = u.data.line_width;
    float _e78 = (_e77 * 0.5);
    out_position = vec4((_e21.x + ((((-(_e71.member_1) * _e78) * 2.0) / _e33) * _e23)), (_e21.y + ((((_e71.member * _e78) * 2.0) / _e38) * _e23)), 0.0, 1.0);
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

