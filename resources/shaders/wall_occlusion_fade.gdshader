shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 tint_color : source_color = vec4(1.0);
uniform float triplanar_scale = 0.5;

uniform vec3 camera_world_pos = vec3(0.0);
uniform int reveal_target_count = 0;
uniform vec4 reveal_target_0 = vec4(0.0);
uniform vec4 reveal_target_1 = vec4(0.0);
uniform vec4 reveal_target_2 = vec4(0.0);
uniform vec4 reveal_target_3 = vec4(0.0);
uniform vec4 reveal_target_4 = vec4(0.0);
uniform vec4 reveal_target_5 = vec4(0.0);
uniform vec4 reveal_target_6 = vec4(0.0);
uniform vec4 reveal_target_7 = vec4(0.0);

uniform float reveal_radius = 1.6;
uniform float reveal_softness = 0.9;
uniform float reveal_strength = 0.9;
uniform float min_alpha = 0.18;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

vec4 _get_reveal_target(int index) {
	if (index == 0) return reveal_target_0;
	if (index == 1) return reveal_target_1;
	if (index == 2) return reveal_target_2;
	if (index == 3) return reveal_target_3;
	if (index == 4) return reveal_target_4;
	if (index == 5) return reveal_target_5;
	if (index == 6) return reveal_target_6;
	return reveal_target_7;
}

float _distance_to_segment_xz(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float ab_len_sq = dot(ab, ab);
	if (ab_len_sq < 0.00001) {
		return length(p - a);
	}
	float t = clamp(dot(p - a, ab) / ab_len_sq, 0.0, 1.0);
	vec2 closest = a + ab * t;
	return length(p - closest);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = normalize(v_world_normal);
	vec3 blend = pow(abs(normal), vec3(4.0));
	blend /= max(dot(blend, vec3(1.0)), 0.0001);

	vec3 wp = v_world_pos * triplanar_scale;
	vec4 tex_x = texture(texture_albedo, wp.yz);
	vec4 tex_y = texture(texture_albedo, wp.xz);
	vec4 tex_z = texture(texture_albedo, wp.xy);
	vec4 tex = tex_x * blend.x + tex_y * blend.y + tex_z * blend.z;

	float reveal = 0.0;
	vec2 cam_xz = camera_world_pos.xz;
	vec2 frag_xz = v_world_pos.xz;
	int count = clamp(reveal_target_count, 0, 8);
	for (int i = 0; i < 8; i++) {
		if (i >= count) {
			break;
		}
		vec4 target = _get_reveal_target(i);
		vec2 target_xz = target.xz;
		float dist = _distance_to_segment_xz(frag_xz, cam_xz, target_xz);
		float target_reveal = 1.0 - smoothstep(reveal_radius - reveal_softness, reveal_radius, dist);
		reveal = max(reveal, target_reveal * target.w);
	}

	ALBEDO = tex.rgb * tint_color.rgb;
	ALPHA = clamp(tex.a * tint_color.a * max(min_alpha, 1.0 - reveal * reveal_strength), 0.0, 1.0);
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
}
