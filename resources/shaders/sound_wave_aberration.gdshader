shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

// ── Wave shape ──
uniform float wave_frequency : hint_range(2.0, 40.0) = 10.0;
uniform float wave_amplitude : hint_range(0.0, 1.0) = 0.25;
uniform float wave_speed : hint_range(0.0, 20.0) = 5.0;
uniform float wave_thickness : hint_range(0.01, 0.5) = 0.12;

// ── Refraction / distortion ──
uniform float refraction_strength : hint_range(0.0, 0.15) = 0.04;
uniform float chromatic_offset : hint_range(0.0, 0.1) = 0.025;

// ── Overall look ──
uniform float edge_fade_power : hint_range(0.5, 6.0) = 2.0;
uniform float pulse_speed : hint_range(0.0, 8.0) = 2.5;
uniform float pulse_amount : hint_range(0.0, 0.5) = 0.12;
uniform float secondary_wave_mix : hint_range(0.0, 1.0) = 0.3;

// ── Rainbow tint ──
uniform float rainbow_intensity : hint_range(0.0, 0.5) = 0.12;
uniform float rainbow_speed : hint_range(0.0, 4.0) = 0.8;
uniform float rainbow_scale : hint_range(0.5, 6.0) = 2.0;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

// HSV to RGB conversion
vec3 hsv2rgb(float h, float s, float val) {
	vec3 c = vec3(h, s, val);
	vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return c.z * mix(vec3(1.0), rgb, c.y);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;

	float u_centered = (u - 0.5) * 2.0;

	// Pulsing amplitude
	float pulse = 1.0 + pulse_amount * sin(TIME * pulse_speed);
	float amp = wave_amplitude * pulse;

	// Primary sinusoidal wave
	float phase = v * wave_frequency - TIME * wave_speed;
	float wave_center = sin(phase) * amp;

	// Secondary harmonic
	float phase2 = v * wave_frequency * 1.7 - TIME * wave_speed * 0.8 + 1.3;
	float wave2 = sin(phase2) * amp * 0.5;
	float combined_wave = mix(wave_center, wave_center + wave2, secondary_wave_mix);

	// Distance from wave center line
	float dist_from_wave = abs(u_centered - combined_wave);

	// Wave mask
	float wave_mask = smoothstep(wave_thickness * 3.0, wave_thickness * 0.1, dist_from_wave);

	// Edge fade along travel direction
	float edge_fade = smoothstep(0.0, 0.1, v) * smoothstep(1.0, 0.9, v);
	edge_fade = pow(edge_fade, edge_fade_power);

	// Side fade
	float side_fade = 1.0 - pow(abs(u_centered), 3.0);
	side_fade = clamp(side_fade, 0.0, 1.0);

	float mask = wave_mask * edge_fade * side_fade;

	// Refraction distortion direction
	float distortion = mask * refraction_strength;
	float wave_deriv = cos(phase) * amp * wave_frequency;
	vec2 distort_dir = vec2(1.0, wave_deriv * 0.3) * distortion;

	// Chromatic aberration: each RGB channel sampled at a different offset
	vec2 base_uv = SCREEN_UV;
	float chroma = chromatic_offset * mask;

	float r = texture(screen_texture, base_uv + distort_dir + vec2(chroma, chroma * 0.5)).r;
	float g = texture(screen_texture, base_uv + distort_dir).g;
	float b = texture(screen_texture, base_uv + distort_dir - vec2(chroma, chroma * 0.5)).b;

	vec3 refracted = vec3(r, g, b);

	// Rainbow iridescent tint shifting along the wave length and over time
	float hue = fract(v * rainbow_scale + u * 0.3 + TIME * rainbow_speed);
	vec3 rainbow = hsv2rgb(hue, 0.7, 1.0);

	// Blend rainbow additively only where the wave is visible
	refracted += rainbow * mask * rainbow_intensity;

	ALBEDO = refracted;
	// Only render the wave area — everything else is fully transparent
	if (mask < 0.01) {
		discard;
	}
	ALPHA = mask;
}
