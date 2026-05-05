shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

uniform vec4 arc_color : source_color = vec4(0.2, 0.8, 1.0, 1.0);
uniform float speed = 15.0;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(p + vec2(0.0, 0.0));
    float b = hash(p + vec2(1.0, 0.0));
    float c = hash(p + vec2(0.0, 1.0));
    float d = hash(p + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 uv = UV;
    float time = TIME * speed;
    
    // Create moving noise patterns
    float n1 = noise(vec2(uv.y * 8.0 - time, uv.x * 6.0));
    float n2 = noise(vec2(uv.y * 15.0 + time * 1.2, uv.x * 12.0));
    
    float combined = (n1 + n2) * 0.5;
    
    // Sharpen to look like lightning
    float intensity = smoothstep(0.45, 0.65, combined);
    
    ALBEDO = arc_color.rgb * 1.5;
    ALPHA = intensity * arc_color.a;
}
