#version 300 es
// Holo Tactical glow (SPEC.md "Glow") as a plain GLSL ES 3.0 full-screen pass, for engines other
// than Godot (godot/addons/holo_tactical/holo_glow.gdshader is the same). Draw it over the 3D
// view with `scene` bound to the rendered picture: the lines' light spreads into a soft glow and
// the dark room falls off at the edges. Two discs of golden-angle samples, a small and a wide one,
// each turned per pixel so their steps blur into fine noise instead of rings.
precision highp float;

uniform sampler2D scene;
uniform vec2 resolution;          // pixels
uniform float near_radius;        // .006  of the picture's height
uniform float wide_radius;        // .03
uniform float near_gain;          // .85
uniform float wide_gain;          // .55
uniform float vignette;           // .35

in vec2 uv;
out vec4 colour;

const int TAPS = 20;

float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * .1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

void main() {
	vec3 base = texture(scene, uv).rgb;
	vec2 aspect = vec2(resolution.y / resolution.x, 1.0);
	float turn = hash(gl_FragCoord.xy) * 6.2832;
	vec3 near = vec3(0.0);
	vec3 wide = vec3(0.0);
	for (int i = 0; i < TAPS; i++) {
		float r = sqrt((float(i) + .5) / float(TAPS));
		float angle = float(i) * 2.39996 + turn;
		vec2 tap = vec2(cos(angle), sin(angle)) * r * aspect;
		near += texture(scene, uv + tap * near_radius).rgb;
		wide += texture(scene, uv + vec2(tap.y, -tap.x) * wide_radius).rgb;
	}
	vec3 light = base + near / float(TAPS) * near_gain + wide / float(TAPS) * wide_gain;
	vec2 centred = uv - .5;
	light *= 1.0 - vignette * clamp(length(centred * vec2(1.0, .9)) * 2.0 - .45, 0.0, 1.0);
	colour = vec4(light, 1.0);
}
