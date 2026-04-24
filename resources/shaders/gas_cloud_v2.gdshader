shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx, unshaded;

uniform vec4 albedo : source_color;
uniform sampler2D texture_albedo : source_color, filter_linear_with_mipmaps, repeat_enable;

void vertex() {
	// Billboard: cząsteczka zawsze patrzy na kamerę (opcjonalnie)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	// Animacja skali na podstawie czasu życia (przekazane przez custom data cząsteczek)
	float fade = INSTANCE_CUSTOM.y; // Standardowo w cząsteczkach y to postęp czasu życia
	VERTEX *= (0.5 + fade * 0.5);
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	ALBEDO = albedo.rgb;
	// Łagodne zanikanie alpha
	float alpha_fade = sin(INSTANCE_CUSTOM.y * PI); 
	ALPHA = tex.a * albedo.a * alpha_fade * (1.0 - INSTANCE_CUSTOM.y);
}
