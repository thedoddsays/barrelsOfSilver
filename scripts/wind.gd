extends Node
## Global wind (autoloaded as `Wind`).
## `angle` is the compass bearing the wind blows TOWARD, in radians.
## Bearing 0 = north = -Z, bearing PI/2 = east = +X.

var angle := deg_to_rad(200.0)  # blowing toward SSW, i.e. coming from NNE
var strength := 0.8             # 0..1

var _t := 0.0
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_noise.seed = randi()
	_noise.frequency = 0.01


func _process(delta: float) -> void:
	_t += delta
	# Slow, natural drift in direction and gusts in strength.
	angle = wrapf(angle + _noise.get_noise_1d(_t) * 0.05 * delta, 0.0, TAU)
	strength = clampf(0.75 + _noise.get_noise_1d(_t * 3.0 + 1000.0) * 0.35, 0.3, 1.0)


func direction() -> Vector3:
	return Vector3(sin(angle), 0.0, -cos(angle))


func knots() -> float:
	return strength * 22.0
