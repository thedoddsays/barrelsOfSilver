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

// Hull mask: the sea is one surface and a ship only rides the average wave, so a crest
// shorter than the ship would poke up through her deck. ocean.gd passes every afloat ship;
// water inside a hull's outline AND above her deck (an open boat's floorboards) isn't drawn.
// Water below the deck is left alone (the hull hides it), so nothing shows through from
// low angles. Sinking ships aren't passed, so the sea closes over them.
const int MAX_HULLS = 96;
uniform int hull_count = 0;
uniform vec4 hull_origin[MAX_HULLS];  // ship origin (world), w = length
uniform vec4 hull_x[MAX_HULLS];  // ship +X (starboard) axis, w = beam
uniform vec4 hull_z[MAX_HULLS];  // ship +Z (aft) axis, w = deck height in ship space

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

// --- Gradient noise ---------------------------------------------------------------
// History: value noise looked blocky/pixelated; a sum of fixed sines looked like a tiled
// image (periodic interference). Gradient noise is smooth AND aperiodic; each octave is
// rotated, scaled by a non-integer factor and drifts its own way, so nothing lines up.

// MurmurHash3 32-bit finalizer (Austin Appleby; public domain).
uint fmix32(uint h) {
	h ^= h >> 16u;
	h *= 2246822507u;
	h ^= h >> 13u;
	h *= 3266489909u;
	h ^= h >> 16u;
	return h;
}

// Integer hash of a lattice point to a gradient in [-1, 1]^2 (stable at large world
// coordinates, unlike the classic sin() hash).
vec2 hash2(vec2 p) {
	uvec2 q = uvec2(ivec2(p) + ivec2(32768));
	uint a = fmix32(q.x * 2654435769u ^ fmix32(q.y));
	uint b = fmix32(a ^ 1759714724u);
	return vec2(float(a), float(b)) * (2.0 / 4294967295.0) - 1.0;
}

// Gradient noise with analytic derivatives: returns (value, d/dx, d/dy).
// Technique after Inigo Quilez's "gradient noise derivatives" article (MIT); see CREDITS.md.
vec3 noised(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	vec2 du = 30.0 * f * f * (f * (f - 2.0) + 1.0);
	vec2 ga = hash2(i);
	vec2 gb = hash2(i + vec2(1.0, 0.0));
	vec2 gc = hash2(i + vec2(0.0, 1.0));
	vec2 gd = hash2(i + vec2(1.0, 1.0));
	float va = dot(ga, f);
	float vb = dot(gb, f - vec2(1.0, 0.0));
	float vc = dot(gc, f - vec2(0.0, 1.0));
	float vd = dot(gd, f - vec2(1.0, 1.0));
	float k = va - vb - vc + vd;
	float value = va + u.x * (vb - va) + u.y * (vc - va) + u.x * u.y * k;
	vec2 deriv = ga + u.x * (gb - ga) + u.y * (gc - ga) + u.x * u.y * (ga - gb - gc + gd)
		+ du * (u.yx * k + vec2(vb, vc) - va);
	return vec3(value, deriv);
}

mat2 rot(float a) {
	float c = cos(a);
	float s = sin(a);
	return mat2(vec2(c, s), vec2(-s, c));
}

// Small-scale ripples: 5 octaves of noise, each with its own size (metres), angle, drift
// and distance fade. Returns the surface slope (d/dx, d/dz).
vec2 ripple_slope(vec2 p, float t, float dist) {
	// size in metres, slope weight, rotation (rad), drift speed (m/s)
	vec4 o[5] = vec4[5](
		vec4(9.0, 0.085, 0.0, 0.9),
		vec4(4.7, 0.07, 1.7, 0.7),
		vec4(2.45, 0.058, 3.9, 0.55),
		vec4(1.3, 0.047, 5.3, 0.45),
		vec4(0.68, 0.036, 2.6, 0.35)
	);
	vec2 slope = vec2(0.0);
	for (int i = 0; i < 5; i++) {
		float size = o[i].x;
		float fade = 1.0 - smoothstep(size * 60.0, size * 200.0, dist);
		if (fade <= 0.0) {
			continue;
		}
		mat2 r = rot(o[i].z);
		vec2 drift = r * vec2(1.0, 0.0) * o[i].w * t;
		vec3 n = noised((r * p + drift) / size);
		// Chain rule back to world space: d/dp = (1/size) * R^T * grad.
		slope += (n.yz * r) * (o[i].y * fade);
	}
	return slope;
}

// Large, slow patches where the wind ruffles the water more or less ("cat's paws").
// This macro variation is what stops the sea reading as one repeated texture.
float wind_patches(vec2 p, float t) {
	float a = noised(rot(0.6) * p / 140.0 + vec2(t * 0.012, t * 0.004)).x;
	float b = noised(rot(2.2) * p / 55.0 - vec2(t * 0.02, -t * 0.01)).x;
	return clamp(0.5 + a * 0.9 + b * 0.5, 0.0, 1.0);
}

// Plan outline matching tools/blender/build_ship.py's lines: bow at -0.625 L, widest at
// -0.094 L, transom at +0.3875 L about 0.6 of the beam wide.
bool inside_hull(vec3 w) {
	for (int i = 0; i < hull_count; i++) {
		vec3 d = w - hull_origin[i].xyz;
		float L = hull_origin[i].w;
		if (dot(d.xz, d.xz) > 0.5 * L * L) {
			continue;
		}
		vec3 X = hull_x[i].xyz;
		vec3 Z = hull_z[i].xyz;
		if (dot(d, cross(Z, X)) < hull_z[i].w) {
			continue;  // below the deck
		}
		float lx = abs(dot(d, X));
		float lz = dot(d, Z);
		float b = 0.5 * hull_x[i].w;
		float zm = -0.094 * L;
		float half_w;
		if (lz < zm) {
			float s = (zm - lz) / (0.531 * L);
			if (s >= 1.0) {
				continue;
			}
			half_w = b * sqrt(1.0 - pow(s, 2.2));
		} else {
			float s = (lz - zm) / (0.4815 * L);
			if (s >= 1.0) {
				continue;
			}
			half_w = b * (1.0 - 0.4 * pow(s, 2.2));
		}
		if (lx < half_w) {
			return true;
		}
	}
	return false;
}

void fragment() {
	if (hull_count > 0 && inside_hull(v_world)) {
		discard;
	}
	vec2 p = v_world.xz;
	float dist = length(CAMERA_POSITION_WORLD - v_world);
	// Fade fine detail with distance so it doesn't shimmer/alias far away.
	float detail = 1.0 - smoothstep(40.0, 350.0, dist);

	float patches = wind_patches(p, wave_time);
	float ruffle = mix(0.45, 1.3, patches);
	vec2 s = ripple_slope(p, wave_time, dist) * ripple_strength * ruffle;
	vec3 n = normalize(v_normal + vec3(-s.x, 0.0, -s.y));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);

	float crest = clamp(v_height * 0.25 + 0.5, 0.0, 1.0);
	vec3 water = mix(deep_color, scatter_color, pow(crest, 2.5));
	// Calm patches read a touch darker and glassier, ruffled ones a touch lighter.
	water *= mix(0.9, 1.08, patches);

	float foam = 1.0 - smoothstep(0.5, 0.72, v_jacobian);
	// Break the crest foam into streaks with noise (was a sin(x)*sin(z) grid).
	float breakup = 0.5 + 0.7 * noised(rot(0.9) * p / 2.8 + vec2(wave_time * 0.25, 0.0)).x
		+ 0.45 * noised(rot(2.4) * p / 1.1 - vec2(0.0, wave_time * 0.3)).x;
	foam *= smoothstep(0.3, 0.7, breakup);
	foam = clamp(foam * foam_amount, 0.0, 1.0);

	ALBEDO = mix(water, foam_color, foam);
	// Slightly rougher with distance (kills sparkly specular aliasing) and in ruffled patches.
	float rough = mix(0.08, 0.16, patches);
	ROUGHNESS = mix(mix(rough, 0.24, 1.0 - detail), 0.7, foam);
	SPECULAR = 0.5;
	METALLIC = 0.0;
}
