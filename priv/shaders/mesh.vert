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
layout(std140) uniform MeshUniforms { MeshUniformsBlock u; };

vec3 a_position_1 = vec3(0.0);

vec3 a_normal_1 = vec3(0.0);

vec4 out_position = vec4(0.0, 0.0, 0.0, 1.0);

vec3 v_normal_2 = vec3(0.0);

layout(location = 0) in vec3 _p2vs_location0;
layout(location = 1) in vec3 _p2vs_location1;
smooth out vec3 _vs2fs_location0;

void function_1() {
    vec3 _e24 = a_position_1;
    vec3 _e25 = a_normal_1;
    type_5 _e28 = u.data.mvp;
    out_position = vec4(((((_e28.member.x * _e24.x) + (_e28.member_1.x * _e24.y)) + (_e28.member_2.x * _e24.z)) + _e28.member_3.x), ((((_e28.member.y * _e24.x) + (_e28.member_1.y * _e24.y)) + (_e28.member_2.y * _e24.z)) + _e28.member_3.y), ((((_e28.member.z * _e24.x) + (_e28.member_1.z * _e24.y)) + (_e28.member_2.z * _e24.z)) + _e28.member_3.z), ((((_e28.member.w * _e24.x) + (_e28.member_1.w * _e24.y)) + (_e28.member_2.w * _e24.z)) + _e28.member_3.w));
    type_6 _e79 = u.data.normal_matrix;
    v_normal_2 = vec3((((_e79.member.x * _e25.x) + (_e79.member_1.x * _e25.y)) + (_e79.member_2.x * _e25.z)), (((_e79.member.y * _e25.x) + (_e79.member_1.y * _e25.y)) + (_e79.member_2.y * _e25.z)), (((_e79.member.z * _e25.x) + (_e79.member_1.z * _e25.y)) + (_e79.member_2.z * _e25.z)));
    return;
}

void main() {
    vec3 a_position = _p2vs_location0;
    vec3 a_normal = _p2vs_location1;
    a_position_1 = a_position;
    a_normal_1 = a_normal;
    function_1();
    float _e7 = out_position.y;
    out_position.y = -(_e7);
    vec4 _e9 = out_position;
    vec3 _e10 = v_normal_2;
    VertexOutput _tmp_return = VertexOutput(_e9, _e10);
    gl_Position = _tmp_return.member;
    _vs2fs_location0 = _tmp_return.member_1;
    gl_Position.yz = vec2(-gl_Position.y, gl_Position.z * 2.0 - gl_Position.w);
    return;
}

