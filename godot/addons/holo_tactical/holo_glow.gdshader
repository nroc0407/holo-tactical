shader_type canvas_item;
// Holo Tactical glow (SPEC.md "Glow"): the hologram's lines spread into a soft glow and the dark
// room falls off at the edges. Put it on the container that shows the 3D view (a
// SubViewportContainer), so HUD drawn above stays sharp; engines with HDR bloom can use theirs.
// Two discs of golden-angle samples, a small and a wide one, each turned per pixel so their steps
// blur into a fine noise instead of rings. shaders/holo_glow.glsl is the same for other engines.

// Glow radii as shares of the picture's height, and how much each adds.
uniform float near_radius = .006;
uniform float wide_radius = .03;
uniform float near_gain = .85;
uniform float wide_gain = .55;
uniform float vignette = .35;
const int TAPS = 20;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void fragment() {
	vec3 base = texture(TEXTURE, UV).rgb;
	// One unit of radius is the picture's height; x is squeezed back by the aspect.
	vec2 scale = vec2(TEXTURE_PIXEL_SIZE.x / TEXTURE_PIXEL_SIZE.y, 1.0);
	float turn = hash(FRAGCOORD.xy) * 6.2832;
	vec3 near = vec3(0.0);
	vec3 wide = vec3(0.0);
	for (int i = 0; i < TAPS; i++) {
		float r = sqrt((float(i) + .5) / float(TAPS));
		float angle = float(i) * 2.39996 + turn;
		vec2 tap = vec2(cos(angle), sin(angle)) * r * scale;
		near += texture(TEXTURE, UV + tap * near_radius).rgb;
		wide += texture(TEXTURE, UV + vec2(tap.y, -tap.x) * wide_radius).rgb;
	}
	vec3 glow = near / float(TAPS) * near_gain + wide / float(TAPS) * wide_gain;
	vec3 light = base + glow;
	vec2 centred = UV - .5;
	light *= 1.0 - vignette * clamp(length(centred * vec2(1.0, .9)) * 2.0 - .45, 0.0, 1.0);
	COLOR = vec4(light, 1.0);
}
