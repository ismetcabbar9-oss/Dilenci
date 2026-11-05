extends Node3D
## Geçici 3D karakter: basit şekillerden oluşan bir insan figürü.
## Yaşa göre boyu büyür, yaşlanınca saçı ağarır, uyurken yatar.
## İleride Sketchfab'den gelecek gerçek bir modelle değiştirilecek.

## true: oyuncunun karakteri (GameState'i izler). false: aile üyesi (setup ile ayarlanır).
var follow_player := true
var age_years := 30.0
var gender := "male"
var shirt_color := Color(0.3, 0.6, 0.9)

var _body_root: Node3D
var _head: MeshInstance3D
var _hair_mat: StandardMaterial3D
var _shirt_mat: StandardMaterial3D
var _time := 0.0
var _target_scale := 1.0
var _was_sleeping := false

const SKIN := Color(0.95, 0.78, 0.62)
const PANTS := Color(0.2, 0.25, 0.4)


func _ready() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	_hair_mat = _mat(Color(0.25, 0.15, 0.08))
	_shirt_mat = _mat(Color(0.95, 0.6, 0.2))
	var skin_mat := _mat(SKIN)
	var pants_mat := _mat(PANTS)

	# Bacaklar
	for x in [-0.12, 0.12]:
		_part(_capsule(0.08, 0.7), pants_mat, Vector3(x, 0.35, 0))
	# Gövde
	_part(_capsule(0.22, 0.75), _shirt_mat, Vector3(0, 0.98, 0))
	# Kollar
	for x in [-0.3, 0.3]:
		var arm := _part(_capsule(0.065, 0.6), _shirt_mat, Vector3(x, 1.0, 0))
		arm.rotation.z = 0.12 * signf(x)
	# Baş
	_head = _part(_sphere(0.2), skin_mat, Vector3(0, 1.55, 0))
	# Saç
	var hair := _part(_sphere(0.21), _hair_mat, Vector3(0, 1.6, -0.02))
	hair.scale = Vector3(1.0, 0.8, 1.0)
	# Gözler
	var eye_mat := _mat(Color(0.1, 0.1, 0.1))
	for x in [-0.07, 0.07]:
		_part(_sphere(0.03), eye_mat, Vector3(x, 1.57, 0.18))

	if follow_player:
		GameState.changed.connect(_refresh)
	_refresh()
	scale = Vector3.ONE * _target_scale


func _process(delta: float) -> void:
	_time += delta
	# Büyümeyi yumuşak göster
	var s := lerpf(scale.x, _target_scale, clampf(delta * 2.0, 0.0, 1.0))
	scale = Vector3.ONE * s

	if follow_player and GameState.sleeping:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, -PI / 2.0, delta * 3.0)
		_body_root.position.y = lerpf(_body_root.position.y, 0.25, delta * 3.0)
		_body_root.scale.y = 1.0 + sin(_time * 1.5) * 0.02  # nefes
	else:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, delta * 5.0)
		var mood: float = GameState.person.needs.fun / 100.0 if follow_player else 0.6
		# Mutluysa hafif zıplar, mutsuzsa yavaş sallanır
		_body_root.position.y = absf(sin(_time * (1.5 + mood * 3.0))) * 0.04 * (0.3 + mood)
		_body_root.scale.y = 1.0
		_head.rotation.y = sin(_time * 0.7) * 0.25


## Aile üyesi figürü için.
func setup(p_age_years: float, p_gender: String, p_shirt: Color) -> void:
	follow_player = false
	age_years = p_age_years
	gender = p_gender
	shirt_color = p_shirt
	if is_inside_tree():
		_refresh()


func _refresh() -> void:
	if follow_player:
		age_years = GameState.get_age_years()
		gender = GameState.person.get("gender", "male")
	var age := age_years
	# 6 yaşta ~0.6, 18 yaşta 1.0 boy
	_target_scale = clampf(0.3 + age * 0.04, 0.35, 1.0)
	if age > 60.0:
		_target_scale -= minf((age - 60.0) * 0.003, 0.06)  # yaşlılıkta hafif kısalma
	# Saç rengi: yaşlandıkça grileşir
	var grey := clampf((age - 45.0) / 30.0, 0.0, 1.0)
	_hair_mat.albedo_color = Color(0.25, 0.15, 0.08).lerp(Color(0.85, 0.85, 0.85), grey)
	if follow_player:
		_shirt_mat.albedo_color = Color(0.85, 0.35, 0.55) if gender == "female" else Color(0.95, 0.6, 0.2)
	else:
		_shirt_mat.albedo_color = shirt_color


func _part(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	_body_root.add_child(mi)
	return mi


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m


func _capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	return c


func _sphere(r: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	return s
