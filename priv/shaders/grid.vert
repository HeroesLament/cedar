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
vec2 a_position_1 = vec2(0.0);

vec2 a_texcoord_1 = vec2(0.0);

vec4 out_position = vec4(0.0, 0.0, 0.0, 1.0);

vec2 v_texcoord_2 = vec2(0.0);

layout(location = 0) in vec2 _p2vs_location0;
layout(location = 1) in vec2 _p2vs_location1;
smooth out vec2 _vs2fs_location0;

void function_1() {
    vec2 _e22 = a_position_1;
    vec2 _e23 = a_texcoord_1;
    out_position = vec4(_e22.x, _e22.y, 0.0, 1.0);
    v_texcoord_2[0u] = _e23.x;
    v_texcoord_2[1u] = _e23.y;
    return;
}

void main() {
    vec2 a_position = _p2vs_location0;
    vec2 a_texcoord = _p2vs_location1;
    a_position_1 = a_position;
    a_texcoord_1 = a_texcoord;
    function_1();
    float _e7 = out_position.y;
    out_position.y = -(_e7);
    vec4 _e9 = out_position;
    vec2 _e10 = v_texcoord_2;
    VertexOutput _tmp_return = VertexOutput(_e9, _e10);
    gl_Position = _tmp_return.member;
    _vs2fs_location0 = _tmp_return.member_1;
    gl_Position.yz = vec2(-gl_Position.y, gl_Position.z * 2.0 - gl_Position.w);
    return;
}

