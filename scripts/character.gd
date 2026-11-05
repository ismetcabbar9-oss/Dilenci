extends Node3D
## 3D insan karakteri — Quaternius modelleri (CC0), bkz. CREDITS.md.
## - 0-12 yaş: büyük kafalı sevimli çocuk modelleri (3 kıyafet çeşidi).
## - 13+ yaş: yetişkin modelleri; kıyafet mesleğe göre (gündelik / takım elbise / işçi).
## - Gerçek animasyonlar (bekleme, yürüme, el sallama, zıplama, yerden alma, oturma...);
##   modelde karşılığı olmayan eylemlerde kollar yönle poza sokulur (yemek, yazı).
## - Yaşa göre boy; yaşlanınca saç ağarır; uyurken yatar.

const PEOPLE := "res://assets/models/people/%s.glb"
const KID_MAX_AGE := 13.0
const SKIN_TONES := [Color(0.98, 0.8, 0.66), Color(0.9, 0.68, 0.52), Color(0.76, 0.55, 0.4)]
# Meslek -> kıyafet
const SUIT_JOBS := ["clerk", "manager", "gm", "ceo", "engineer", "teacher", "sales", "doctor"]
const WORKER_JOBS := ["worker", "master", "courier"]

## Eylem -> [çocuk animasyonu, yetişkin animasyonu] ("" = animasyon yok, kollar yönle)
const ACTION_ANIMS := {
	"eat": ["PickUp", ""],
	"wash": ["PickUp", "Interact"],
	"play": ["Jump", "Wave"],
	"study": ["SitDown", ""],
	"work": ["SitDown", ""],
	"manage": ["Victory", ""],
	"social": ["Victory", "Wave"],
	"date": ["Victory", "Wave"],
}
const ACTION_SECONDS := 2.2

## true: oyuncunun karakteri (GameState'i izler). false: aile üyesi (setup ile ayarlanır).
var follow_player := true
var age_years := 30.0
var gender := "male"
var variant := 0          # Kardeşler / eş için farklı kıyafet çeşidi
var outfit := ""          # "" = mesleğe göre otomatik
var shirt_color := Color.WHITE  # (eski arayüzle uyum için)

var _body_root: Node3D
var _model: Node3D
var _model_key := ""
var _model_height := 1.8
var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _is_kid_rig := false
var _rig := {}
var _hair_mats: Array = []
var _idle_anim := ""
var _walk_anim := ""
var _time := 0.0
var _target_scale := 1.0
var _moving := false
var _pending_action := ""
var _pending_wait := 0.0
var _action_kind := ""
var _action_time := 99.0
var _aim_kind := ""        # Animasyonsuz eylemde kol pozu


func _ready() -> void:
	_body_root = Node3D.new()
	add_child(_body_root)
	_time = randf() * 10.0
	if follow_player:
		GameState.changed.connect(_refresh)
	_refresh()
	scale = Vector3.ONE * _target_scale


## Aile üyesi figürü için.
func setup(p_age_years: float, p_gender: String, p_shirt: Color, p_variant: int = 0, p_outfit: String = "") -> void:
	follow_player = false
	age_years = p_age_years
	gender = p_gender
	shirt_color = p_shirt
	variant = p_variant
	outfit = p_outfit
	if is_inside_tree():
		_refresh()


func _refresh() -> void:
	if follow_player:
		age_years = GameState.get_age_years()
		gender = GameState.person.get("gender", "male")
	var key := _choose_model()
	if key != _model_key:
		_load_model(key)
	# Boy: çocuk 6 yaş ~1.0 m, 12 yaş ~1.3 m; yetişkin 13 → 1.5 m, 18+ → 1.75 m; yaşlılıkta hafif kısalma
	var h: float
	if age_years < KID_MAX_AGE:
		h = 0.7 + age_years * 0.05
	else:
		h = lerpf(1.5, 1.75, clampf((age_years - 13.0) / 5.0, 0.0, 1.0))
		if age_years > 60.0:
			h -= minf((age_years - 60.0) * 0.004, 0.08)
		if gender == "female":
			h -= 0.07
	_target_scale = h / maxf(_model_height, 0.01)
	# Saç yaşla ağarır
	var grey := clampf((age_years - 45.0) / 30.0, 0.0, 1.0)
	for pair in _hair_mats:
		pair[0].albedo_color = pair[1].lerp(Color(0.82, 0.82, 0.8), grey)


func _choose_model() -> String:
	var g := "girl" if gender == "female" else "boy"
	if age_years < KID_MAX_AGE:
		return "kid_%s_%d" % [g, (variant % 3) + 1]
	var who := "woman" if gender == "female" else "man"
	var o := outfit
	if o == "":
		var job: String = GameState.person.get("job", "") if follow_player else ""
		if job in SUIT_JOBS:
			o = "suit"
		elif job in WORKER_JOBS:
			o = "worker"
		else:
			o = "casual"
	if o == "alt":
		o = "formal" if who == "woman" else "hoodie"
	return "%s_%s" % [who, o]


func _load_model(key: String) -> void:
	if _model:
		_model.queue_free()
	_model_key = key
	_is_kid_rig = key.begins_with("kid_")
	_rig = {}
	_hair_mats = []
	_anim = null
	_skeleton = null
	_model = load(PEOPLE % key).instantiate()
	_body_root.add_child(_model)

	# Malzemeler: çocuklarda ten ve gözler, herkeste saç (yaşla ağarmak için kopyalanır)
	var tone: Color = SKIN_TONES[0] if follow_player else SKIN_TONES[abs(hash(str(variant) + gender)) % SKIN_TONES.size()]
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m == null:
				continue
			var nm := m.resource_name
			if _is_kid_rig and nm == "Skin":
				var c := m.duplicate() as BaseMaterial3D
				c.albedo_color = tone
				mi.set_surface_override_material(si, c)
			elif _is_kid_rig and nm == "Face":
				var c2 := m.duplicate() as BaseMaterial3D
				c2.albedo_color = Color(0.13, 0.09, 0.08)
				mi.set_surface_override_material(si, c2)
			elif nm.begins_with("Hair"):
				var c3 := m.duplicate() as BaseMaterial3D
				mi.set_surface_override_material(si, c3)
				_hair_mats.append([c3, m.albedo_color])

	# Model yüksekliği (boy ölçeklemek için)
	var box := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = _model.global_transform.affine_inverse() * (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	_model_height = maxf(box.size.y, 0.1)
	_model.position.y = -box.position.y

	var sks := _model.find_children("*", "Skeleton3D", true, false)
	_skeleton = sks[0] if not sks.is_empty() else null
	if _skeleton:
		for key2 in ["UpperArm.L", "LowerArm.L", "UpperArm.R", "LowerArm.R", "Head", "Torso", "Neck"]:
			var bi := _skeleton.find_bone(key2)
			if bi >= 0:
				_rig[key2] = bi

	var aps := _model.find_children("*", "AnimationPlayer", true, false)
	if not aps.is_empty():
		_anim = aps[0]
		_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_idle_anim = _find_anim("Idle")
		_walk_anim = _find_anim("Walk")
		for a in [_idle_anim, _walk_anim, _find_anim("Run")]:
			if a != "":
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		if _idle_anim != "":
			_anim.play(_idle_anim)
			_anim.seek(randf() * 1.0, true)


func _find_anim(name: String) -> String:
	if _anim == null or name == "":
		return ""
	for a in _anim.get_animation_list():
		var s := String(a)
		if s == name or s.ends_with("|" + name) or s.ends_with("/" + name):
			return s
	return ""


# ---------------------------------------------------------------
# Hareket ve eylemler
# ---------------------------------------------------------------
## Yürürken yürüme animasyonu; varınca bekleyen eylemi oynat.
func set_moving(m: bool) -> void:
	if m == _moving:
		return
	_moving = m
	if m:
		_action_kind = ""
		_aim_kind = ""
		_pending_wait = 0.0
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
	_pending_wait = 0.0


func _start_action(kind: String) -> void:
	_action_kind = kind
	_action_time = 0.0
	_aim_kind = ""
	if _anim == null:
		return
	var pair: Array = ACTION_ANIMS.get(kind, ["", ""])
	var a := _find_anim(pair[0] if _is_kid_rig else pair[1])
	if a != "":
		_anim.get_animation(a).loop_mode = Animation.LOOP_NONE
		_anim.play(a, 0.2)
	else:
		# Animasyon yok: bekleme üstüne kol pozu
		_aim_kind = kind
		if _idle_anim != "":
			_anim.play(_idle_anim, 0.2)


func _process(delta: float) -> void:
	_time += delta
	_action_time += delta
	var s := lerpf(scale.x, _target_scale, clampf(delta * 2.0, 0.0, 1.0))
	scale = Vector3.ONE * s

	# Yürümeye gerek kalmadıysa (zaten oradaysa) bekleyen eylemi kısa süre sonra başlat
	if _pending_action != "" and not _moving:
		_pending_wait += delta
		if _pending_wait > 0.15:
			_start_action(_pending_action)
			_pending_action = ""

	var asleep := follow_player and GameState.sleeping
	if _anim:
		# Tek seferlik eylem animasyonu bitince bekleme animasyonuna dön
		if not asleep and not _moving and _action_kind != "" and _aim_kind == "" and not _anim.is_playing() and _idle_anim != "":
			_action_kind = ""
			_anim.play(_idle_anim, 0.3)
		_anim.advance(0.0 if asleep else delta)

	if asleep:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, -PI / 2.0, delta * 3.0)
		_body_root.position.y = lerpf(_body_root.position.y, 0.25, delta * 3.0)
	else:
		_body_root.rotation.x = lerpf(_body_root.rotation.x, 0.0, delta * 5.0)
		_body_root.position.y = lerpf(_body_root.position.y, 0.0, delta * 5.0)

	if _aim_kind != "" and _action_time < ACTION_SECONDS and not asleep and not _moving:
		_apply_aim_pose(_aim_kind, _time, clampf(minf(_action_time * 4.0, (ACTION_SECONDS - _action_time) * 4.0), 0.0, 1.0))
	elif _aim_kind != "" and _action_time >= ACTION_SECONDS:
		_aim_kind = ""
		_action_kind = ""


# ---------------------------------------------------------------
# Animasyonsuz eylemler için kol pozları (karakter uzayında yönler)
# Karakter uzayı: +Z ileri (yüz), +X karakterin solu, +Y yukarı.
# ---------------------------------------------------------------
func _action_arm_targets(kind: String, t: float) -> Array:
	var l_up := Vector3(0.18, -1.0, 0.0)
	var l_lo := Vector3(0.1, -1.0, 0.25)
	match kind:
		"eat":  # Sağ el ağza
			return [l_up, l_lo, Vector3(-0.25, -0.75, 0.6), Vector3(0.35, 0.9 + sin(t * 9.0) * 0.25, 0.2)]
		"wash":
			var rub := sin(t * 10.0) * 0.3
			return [Vector3(0.7, 0.7, 0.1), Vector3(-0.8, 0.4 + rub, 0.1), Vector3(-0.7, 0.7, 0.1), Vector3(0.8, 0.4 - rub, 0.1)]
		"study", "work", "manage":  # Eğilip yazma
			var tap := sin(t * 14.0) * 0.12
			return [Vector3(0.25, -0.8, 0.55), Vector3(-0.15, -0.15 + tap, 1.0), Vector3(-0.25, -0.8, 0.55), Vector3(0.15, -0.15 - tap, 1.0)]
		"play", "social", "date":
			return [l_up, l_lo, Vector3(-1.0, 0.45, 0.1), Vector3(-0.25 + sin(t * 10.0) * 0.45, 1.0, 0.1)]
	return []


func _apply_aim_pose(kind: String, t: float, fade: float) -> void:
	if not _skeleton or fade <= 0.0:
		return
	var tl := _action_arm_targets(kind, t)
	if tl.is_empty():
		return
	if kind in ["study", "work", "manage"] and _rig.has("Head"):
		var hb: int = _rig["Head"]
		var cur := _skeleton.get_bone_pose_rotation(hb)
		_skeleton.set_bone_pose_rotation(hb, cur.slerp(cur * Quaternion(Vector3(1, 0, 0), 0.35), fade))
	_aim_arm("UpperArm.L", "LowerArm.L", tl[0], tl[1], fade)
	_aim_arm("UpperArm.R", "LowerArm.R", tl[2], tl[3], fade)


func _aim_arm(arm_key: String, fore_key: String, up_dir: Vector3, lo_dir: Vector3, fade: float) -> void:
	if not (_rig.has(arm_key) and _rig.has(fore_key)):
		return
	var arm: int = _rig[arm_key]
	var fore: int = _rig[fore_key]
	var kids := _skeleton.get_bone_children(fore)
	if kids.is_empty():
		return
	var hand: int = kids[0]
	var to_skel := _skeleton.global_transform.basis.inverse() * global_transform.basis
	var parent := _skeleton.get_bone_parent(arm)
	var parent_g: Transform3D = _skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var arm_g := _aim_one(arm, fore, parent_g, (to_skel * up_dir).normalized(), fade)
	_aim_one(fore, hand, arm_g, (to_skel * lo_dir).normalized(), fade)


func _aim_one(bone: int, child: int, parent_g: Transform3D, dir: Vector3, fade: float) -> Transform3D:
	var cur_local := _skeleton.get_bone_pose(bone)
	var g := parent_g * cur_local
	var cur := (g.basis * _skeleton.get_bone_pose(child).origin).normalized()
	if cur.length() < 0.001 or dir.length() < 0.001:
		return g
	var q := Quaternion(cur, dir) if cur.dot(dir) > -0.999 else Quaternion(g.basis.x.normalized(), PI)
	q = Quaternion.IDENTITY.slerp(q, fade)
	var new_basis := Basis(q) * g.basis
	var local := parent_g.basis.inverse() * new_basis
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
	return Transform3D(new_basis, g.origin)
