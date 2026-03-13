shader_type canvas_item;

// The color of the vignette
uniform vec4 vignette_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);

// How intense the vignette is. 0.0 = invisible, 1.0 = full red screen
uniform float intensity = 0.0;

void fragment() {
    // Get the normalized UV coordinates
    vec2 uv = UV;

    // Calculate distance from the center (0.5, 0.5)
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(uv, center);
    
    // Scale distance so it reaches 1.0 at the corners (max distance is approx 0.707)
    dist = smoothstep(0.4, 0.8, dist);
    
    // The final alpha depends on distance from center and the global intensity
    float alpha = dist * intensity;
    
    // Output the color with calculated alpha
    COLOR = vec4(vignette_color.rgb, vignette_color.a * alpha);
}
