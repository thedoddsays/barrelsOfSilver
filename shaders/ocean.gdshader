shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Four Gerstner waves: (dir.x, dir.y, steepness, wavelength). Set from ocean.gd so
// the CPU buoyancy maths and the GPU surface always agree.
uniform float wave_time = 0.0;
uniform vec4 wave_a = vec4(1.0, 0.3, 0.14, 60.0);
uniform vec4 wave_b = vec4(0.6, 1.0, 0.13, 33.0);
uniform vec4 wave_c = vec4(-0.3, 1.0, 0.12, 21.0);
uniform vec4 wave_d = vec4(0.8, -0.5, 0.08, 13.0);

uniform vec3 deep_color : source_color = vec3(0.01, 0.07, 0.12);
uniform vec3 scatter_color : source_color = vec3(0.03, 0.34, 0.38);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.97);
uniform float foam_amount = 1.0;
uniform float ripple_strength = 1.0;

varying vec3 v_world;
varying vec3 v_normal;
varying float v_height;
varying float v_jacobian;

const float GRAVITY = 9.8;

vec3 gerstner(vec4 wave, vec2 p, inout vec3 tangent, inout vec3 binormal) {
	float steepness = wave.z;
	float k = 2.0 * PI / wave.w;
	float c = sqrt(GRAVITY / k);
	vec2 d = normalize(wave.xy);
	float f = k * (dot(d, p) - c * wave_time);
	float a = steepness / k;
	float s = sin(f);
	float co = cos(f);
	tangent += vec3(-d.x * d.x * steepness * s, d.x * steepness * co, -d.x * d.y * steepness * s);
	binormal += vec3(-d.x * d.y * steepness * s, d.y * steepness * co, -d.y * d.y * steepness * s);
	return vec3(d.x * a * co, a * s, d.y * a * co);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec3 disp = vec3(0.0);
	disp += gerstner(wave_a, world.xz, tangent, binormal);
	disp += gerstner(wave_b, world.xz, tangent, binormal);
	disp += gerstner(wave_c, world.xz, tangent, binormal);
	disp += gerstner(wave_d, world.xz, tangent, binormal);
	VERTEX += disp; // the ocean node is only ever translated, so world == local offsets
	v_world = world + disp;
	v_normal = normalize(cross(binormal, tangent));
	v_height = disp.y;
	// Jacobian of the horizontal displacement: < 1 where the surface bunches up (crests).
	v_jacobian = tangent.x * binormal.z - tangent.z * binormal.x;
}

// Small-scale ripples as a sum of smooth directional sine waves. (The previous grid-based
// value noise produced blocky, pixelated-looking highlights.) Returns the slope (d/dx, d/dz).
vec2 ripple_slope(vec2 p, float t) {
	vec2 slope = vec2(0.0);
	// direction (normalised in loop), frequency, speed, amplitude
	vec4 r[6] = vec4[6](
		vec4(0.83, 0.56, 0.9, 1.3),
		vec4(-0.42, 0.91, 1.3, 1.6),
		vec4(0.97, -0.24, 1.9, 2.1),
		vec4(-0.71, -0.70, 2.7, 2.4),
		vec4(0.12, 0.99, 3.8, 2.9),
		vec4(0.60, -0.80, 5.1, 3.3)
	);
	for (int i = 0; i < 6; i++) {
		vec2 d = normalize(r[i].xy);
		float freq = r[i].z;
		float phase = dot(d, p) * freq - t * r[i].w;
		float amp = 0.05 / freq;
		slope += d * cos(phase) * freq * amp;
	}
	return slope;
}

void fragment() {
	vec2 p = v_world.xz;
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	// Fade fine detail with distance so it doesn't shimmer/alias far away.
	float detail = 1.0 - smoothstep(40.0, 350.0, dist);

	vec2 s = ripple_slope(p, wave_time) * ripple_strength * detail;
	vec3 n = normalize(v_normal + vec3(-s.x, 0.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float crest = clamp(v_height * 0.25 + 0.5, 0.0, 1.0);
	vec3 water = mix(deep_color, scatter_color, pow(crest, 2.5));

	float foam = 1.0 - smoothstep(0.5, 0.72, v_jacobian);
	float breakup = 0.5 + 0.25 * sin(p.x * 0.9 + wave_time * 0.7) * sin(p.y * 0.7 - wave_time * 0.5)
		+ 0.25 * sin((p.x + p.y) * 0.35 + wave_time * 0.3);
	foam *= smoothstep(0.3, 0.7, breakup);
	foam = clamp(foam * foam_amount, 0.0, 1.0);

	ALBEDO = mix(water, foam_color, foam);
	// Slightly rougher with distance: kills sparkly specular aliasing.
	ROUGHNESS = mix(mix(0.1, 0.22, 1.0 - detail), 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
