#version 410 core
struct ShapeUniformsData {
    vec4 fill_color;
    vec4 fill_color1;
    vec4 stroke_color;
    vec4 radii;
    vec4 rect;
    vec4 gradient;
    vec4 wedge;
    vec2 viewport;
    vec2 arc;
    float stroke_width;
    float shape;
    float gradient_kind;
    float inset;
    float pixel_scale;
};
struct ShapeUniformsBlock {
    ShapeUniformsData data;
};
struct VertexOutput {
    vec2 member;
    vec4 member_1;
};
layout(std140) uniform ShapeUniforms { ShapeUniformsBlock u; };

vec2 a_corner_1 = vec2(0.0);

vec2 v_local_2 = vec2(0.0);

vec4 out_position = vec4(0.0, 0.0, 0.0, 1.0);

layout(location = 0) in vec2 _p2vs_location0;
smooth out vec2 _vs2fs_location0;

void function_1() {
    vec2 _e35 = a_corner_1;
    float _e40 = u.data.stroke_width;
    float _e42 = ((_e40 * 0.5) + 2.0);
    float _e46 = u.data.rect[2u];
    float _e47 = (_e42 * 2.0);
    float _e52 = u.data.rect[3u];
    float _e57 = u.data.rect[0u];
    float _e60 = ((_e57 - _e42) + (_e35.x * (_e46 + _e47)));
    float _e64 = u.data.rect[1u];
    float _e67 = ((_e64 - _e42) + (_e35.y * (_e52 + _e47)));
    v_local_2[0u] = (_e60 - (_e57 + (_e46 * 0.5)));
    v_local_2[1u] = (_e67 - (_e64 + (_e52 * 0.5)));
    float _e79 = u.data.viewport[0u];
    float _e86 = u.data.viewport[1u];
    out_position = vec4((((_e60 / _e79) * 2.0) - 1.0), (1.0 - ((_e67 / _e86) * 2.0)), 0.0, 1.0);
    return;
}

void main() {
    vec2 a_corner = _p2vs_location0;
    a_corner_1 = a_corner;
    function_1();
    float _e5 = out_position.y;
    out_position.y = -(_e5);
    vec2 _e7 = v_local_2;
    vec4 _e8 = out_position;
    VertexOutput _tmp_return = VertexOutput(_e7, _e8);
    _vs2fs_location0 = _tmp_return.member;
    gl_Position = _tmp_return.member_1;
    gl_Position.yz = vec2(-gl_Position.y, gl_Position.z * 2.0 - gl_Position.w);
    return;
}

