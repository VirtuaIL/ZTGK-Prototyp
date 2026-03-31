@tool
extends Area3D
class_name HeatGrate

static var _shared_mat_cold: Material
static var _shared_mat_hot: Material

@export var is_active: bool = false:
	set(val):
		is_active = val
		_update_visuals()

var _mesh: MeshInstance3D

func _ready() -> void:
	_mesh = get_node_or_null("MeshInstance3D")
	_ensure_shared_materials()
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
	_update_visuals()

static func _ensure_shared_materials() -> void:
	if _shared_mat_cold != null:
		return

	var cold := StandardMaterial3D.new()
	cold.albedo_color = Color(0.08, 0.08, 0.08)
	cold.roughness = 0.85
	_shared_mat_cold = cold

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded;

varying vec3 local_pos;

uniform vec4 color_dark   : source_color = vec4(0.04, 0.01, 0.00, 1.0);
uniform vec4 color_magma  : source_color = vec4(0.85, 0.14, 0.01, 1.0);
uniform vec4 color_orange : source_color = vec4(1.00, 0.42, 0.03, 1.0);
uniform vec4 color_core   : source_color = vec4(1.00, 0.88, 0.20, 1.0);
uniform float flow_speed  : hint_range(0.1, 4.0) = 1.9;
uniform float lava_scale  : hint_range(1.0, 16.0) = 3.0;
uniform float emit_power  : hint_range(0.5, 5.0) = 0.6;

void vertex() {
    local_pos = VERTEX;
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
        mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p  = p * 2.1 + vec2(1.3, 0.7);
        a *= 0.5;
    }
    return v;
}

void fragment() {
    vec2 p = local_pos.xz * lava_scale;
    float t = TIME * flow_speed;

    vec2 q = vec2(
        fbm(p + vec2(0.0, t * 0.4)),
        fbm(p + vec2(5.2, t * 0.3))
    );
    vec2 r = vec2(
        fbm(p + 4.0 * q + vec2(1.7, t * 0.35)),
        fbm(p + 4.0 * q + vec2(9.2, t * 0.25))
    );
    float f = fbm(p + 4.0 * r);

    float crack = smoothstep(0.35, 0.72, f);
    float core  = smoothstep(0.62, 0.85, f + 0.08 * sin(t * 4.0 + p.x * 2.0));

    vec3 col = mix(color_dark.rgb,   color_magma.rgb,  crack);
    col      = mix(col,              color_orange.rgb, crack * crack);
    col      = mix(col,              color_core.rgb,   core);

    float pulse = 0.82 + 0.28 * sin(t * 3.5 + p.x * 1.1 + p.y * 0.8);
    float glow  = crack * 1.4 + core * 2.2;

    ALBEDO   = col;
    EMISSION = col * (1.0 + glow * emit_power * pulse);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_shared_mat_hot = mat

func _update_visuals() -> void:
	if _mesh == null:
		return
	_mesh.material_override = _shared_mat_hot if is_active else _shared_mat_cold

func _on_body_entered(body: Node3D) -> void:
	if not is_active:
		return
	if body.has_method("die"):
		body.die()
		return
	# Rat delegates death to its player — keep this only if Rat.die() doesn't exist
	if body is Rat and body.player != null and body.player.has_method("die"):
		body.player.die()
