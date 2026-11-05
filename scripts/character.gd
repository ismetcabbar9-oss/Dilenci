extends Node3D
## 3D insan karakteri (Sketchfab modelleri, bkz. CREDITS.md).
## - Cinsiyete göre erkek/kadın modeli yüklenir.
## - Yaşa göre boy ölçeklenir; çocukken kafa orantılı olarak büyük görünür.
## - Modelde "idle" animasyonu varsa oynatılır, yoksa kemiklerle nefes/sallanma yapılır.
## - Uyurken yatar.

const MODELS := {
	"male": "res://assets/models/characters/man.glb",
	"female": "res://assets/models/characters/woman.glb",
}
const ADULT_HEIGHT := 1.75

## true: oyuncunun karakteri (GameState'i izler). false: aile üyesi (setup ile ayarlanır).
var follow_player := true
var age_years := 30.0
var gender := "male"
var shirt_color := Color.WHITE  # (eski arayüzle uyum için; şimdilik kullanılmıyor)

var _body_root: Node3D
var _model: Node3D
var _model_gender := ""
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _head_bone := -1
var _spine_bone := -1
var _time := 0.0
var _target_scale := 1.0
var _head_scale := 1.0
var _leg_scale := 1.0
var _leg_bones: Array[int] = []
var _hip_height := 0.9
var _idle_anim := ""
var _walk_anim := ""
var _moving := false
var _pending_action := ""
var _action_kind := ""
var _action_time := 0.0
const ACTION_ANIMS := {"play": "jump", "eat": "picking", "wash": "picking"}


func _ready() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	_time = randf() * 10.0
	if follow_player:
		GameState.changed.connect(_refresh)
	_refresh()
	scale = Vector3.ONE * _target_scale


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
	if gender != _model_gender:
		_load_model()
	var age := age_years
	# Boy: 6 yaşta ~%60, 18 yaşta %100
	_target_scale = clampf(0.3 + age * 0.04, 0.35, 1.0)
	if age > 60.0:
		_target_scale -= minf((age - 60.0) * 0.003, 0.06)  # yaşlılıkta hafif kısalma
	# Çocukken kafa gövdeye göre daha büyük
	var growth := clampf((age - 2.0) / 15.0, 0.0, 1.0)
	_head_scale = lerpf(1.55, 1.0, growth)
	_leg_scale = lerpf(0.78, 1.0, growth)


func _load_model() -> void:
	if _model:
		_model.queue_free()
	_model_gender = gender
	_anim = null
	_skeleton = null
	_head_bone = -1
	_spine_bone = -1
	_leg_bones.clear()
	_idle_anim = ""
	_walk_anim = ""
	var scene: PackedScene = load(MODELS.get(gender, MODELS.male))
	_model = scene.instantiate()
	_body_root.add_child(_model)

	_skeleton = _find(_model, "Skeleton3D") as Skeleton3D
	if _skeleton:
		for i in _skeleton.get_bone_count():
			var n := _skeleton.get_bone_name(i).to_lower()
			if _head_bone < 0 and n.contains("head") and not n.contains("end") and not n.contains("top"):
				_head_bone = i
			if _spine_bone < 0 and n.contains("spine"):
				_spine_bone = i
			if n.contains("thigh") or n.contains("upleg"):
				_leg_bones.append(i)

	# Boyu normalize et: kafa kemiği yüksekliği ≈ boyun %87'si.
	# (Skinned mesh kutuları iskelet dönüşümünü yansıtmadığı için kemikten ölçülüyor.)
	if _skeleton and _head_bone >= 0:
		var head_global := _skeleton.global_transform * _skeleton.get_bone_global_rest(_head_bone)
		var head_y := (_body_root.global_transform.affine_inverse() * head_global).origin.y
		if head_y > 0.01:
			_model.scale = Vector3.ONE * (ADULT_HEIGHT * 0.87 / head_y)
		if not _leg_bones.is_empty():
			var hip_global := _skeleton.global_transform * _skeleton.get_bone_global_rest(_leg_bones[0])
			_hip_height = (_body_root.global_transform.affine_inverse() * hip_global).origin.y

	_anim = _find(_model, "AnimationPlayer") as AnimationPlayer
	if _anim:
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_idle_anim = _pick_anim(["idle"], ["fight"])
		_walk_anim = _pick_anim(["walk"], [])
		if _idle_anim != "":
			_anim.get_animation(_idle_anim).loop_mode = Animation.LOOP_LINEAR
			if _walk_anim != "":
				_anim.get_animation(_walk_anim).loop_mode = Animation.LOOP_LINEAR
			_anim.play(_idle_anim)
		else:
			_anim = null  # Sadece duruş pozu var; kemik animasyonu kullanılacak


## Yürürken yürüme animasyonu; varınca bekleyen eylemi oynat.
func set_moving(m: bool) -> void:
	if m == _moving:
		return
	_moving = m
	if m:
		_action_kind = ""
		if _anim and _walk_anim != "":
			_anim.play(_walk_anim, 0.2)
	else:
		if _pending_action != "":
			_start_action(_pending_action)
			_pending_action = ""
		elif _anim and _idle_anim != "":
			_anim.play(_idle_anim, 0.2)


## Eylem tepkisi (hedefe varınca oynar).
func play_action(kind: String) -> void:
	_pending_action = kind


func _start_action(kind: String) -> void:
	_action_kind = kind
	_action_time = 0.0
	if _anim:
		var key: String = ACTION_ANIMS.get(kind, "")
		var a := _pick_anim([key], []) if key != "" else ""
		if a != "":
			_anim.get_animation(a).loop_mode = Animation.LOOP_NONE
			_anim.play(a, 0.2)
			_action_kind = "anim"
			return
		if _idle_anim != "":
			_anim.play(_idle_anim, 0.2)


func _process(delta: float) -> void:
	_time += delta
	_action_time += delta
	# Animasyonlu eylem bitince bekleme animasyonuna dön
	if _action_kind == "anim" and _anim and not _anim.is_playing():
		_action_kind = ""
		if _idle_anim != "":
			_anim.play(_idle_anim, 0.3)
	var s := lerpf(scale.x, _target_scale, clampf(delta * 2.0, 0.0, 1.0))
	scale = Vector3.ONE * s

	var asleep := follow_player and GameState.sleeping
	if _anim:
		_anim.advance(0.0 if asleep else delta)

	if asleep:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, -PI / 2.0, delta * 3.0)
		_body_root.position.y = lerpf(_body_root.position.y, 0.25, delta * 3.0)
	else:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, delta * 5.0)
		var y := 0.0
		# Animasyonu olmayan model için basit eylem tepkileri (~1.5 sn)
		if _action_time < 1.5:
			match _action_kind:
				"play", "social", "date":
					y = absf(sin(_action_time * 7.0)) * 0.25 * (1.5 - _action_time)
				"eat", "wash", "study", "work", "manage":
					_body_root.rotation.x = sin(_action_time * 6.0) * 0.08
		_body_root.position.y = lerpf(_body_root.position.y, y, delta * 12.0)
		if _moving and _anim == null:
			_body_root.position.y = absf(sin(_time * 9.0)) * 0.05  # yürüme sekmesi

	_apply_bones(asleep)


## Animasyondan SONRA kemik ayarları: çocuk kafası, nefes/sallanma.
func _apply_bones(asleep: bool) -> void:
	if not _skeleton:
		return
	if _head_bone >= 0:
		_skeleton.set_bone_pose_scale(_head_bone, Vector3.ONE * _head_scale)
	# Çocukken bacaklar kısa; model yere değsin diye aşağı kaydırılır
	for b in _leg_bones:
		_skeleton.set_bone_pose_scale(b, Vector3.ONE * _leg_scale)
	_model.position.y = -_hip_height * (1.0 - _leg_scale)
	if _anim == null and _spine_bone >= 0:
		var rest := _skeleton.get_bone_rest(_spine_bone).basis.get_rotation_quaternion()
		var speed := 0.6 if asleep else 1.2
		var amount := 0.015 if asleep else 0.04
		var sway := Quaternion(Vector3(0, 0, 1), sin(_time * speed) * amount) \
			* Quaternion(Vector3(1, 0, 0), sin(_time * speed * 2.0) * amount * 0.5)
		_skeleton.set_bone_pose_rotation(_spine_bone, rest * sway)


func _pick_anim(include: Array, exclude: Array) -> String:
	for a in _anim.get_animation_list():
		var n := String(a).to_lower()
		var ok := true
		for w in include:
			ok = ok and n.contains(w)
		for w in exclude:
			ok = ok and not n.contains(w)
		if ok:
			return a
	return ""


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for c in node.get_children():
		var r := _find(c, cls)
		if r:
			return r
	return null

