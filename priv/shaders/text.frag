#version 410 core
struct TextUniformsData {
    vec4 color;
    vec2 viewport;
    float px_range;
};
struct TextUniformsBlock {
    TextUniformsData data;
};
struct VertexOutput {
    vec4 member;
    vec2 member_1;
};
vec2 v_texcoord_1 = vec2(0.0);

layout(std140) uniform TextUniforms { TextUniformsBlock u; };

uniform sampler2D u_atlas;

vec4 output_ = vec4(0.0);

smooth in vec2 _vs2fs_location0;
layout(location = 0) out vec4 _fs2p_location0;

void function() {
    float phi_70_ = 0.0;
    vec2 _e17 = v_texcoord_1;
    vec4 _e18 = texture(u_atlas, vec2(_e17));
    float _e22 = u.data.px_range;
    float _e25 = (((_e18.x - 0.5) * _e22) + 0.5);
    if ((_e25 < 0.0)) {
        phi_70_ = 0.0;
    } else {
        phi_70_ = ((_e25 > 1.0) ? 1.0 : _e25);
    }
    float _e30 = phi_70_;
    float _e34 = u.data.color[0u];
    float _e38 = u.data.color[1u];
    float _e42 = u.data.color[2u];
    float _e46 = u.data.color[3u];
    output_ = vec4(_e34, _e38, _e42, (_e46 * _e30));
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

