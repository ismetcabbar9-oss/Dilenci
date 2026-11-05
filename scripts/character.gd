extends Node3D
## 3D insan karakteri (Sketchfab modelleri, bkz. CREDITS.md).
## - Cinsiyete göre erkek/kadın modeli yüklenir.
## - Yaşa göre boy ölçeklenir; çocukken kafa orantılı olarak büyük görünür.
## - Modelde "idle" animasyonu varsa oynatılır, yoksa kemiklerle nefes/sallanma yapılır.
## - Uyurken yatar.

const MODELS := {
	"male": "res://assets/models/characters/man.glb",
	"female": "res://assets/models/characters/woman.glb",
	"kid_male": "res://assets/models/kids/kid_boy.glb",
	"kid_female": "res://assets/models/kids/kid_girl.glb",
}
const KID_MODEL_MAX_AGE := 12.0  # Bu yaşa kadar çocuk modeli
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
var _arm_bones: Array[int] = []   # T-pozundaki çocuk modellerinin kolları indirilir
## Mixamo iskeletli modeller (kadın, çocuklar) için kodla animasyon: kemik adı -> indeks
var _rig := {}
var _is_mixamo := false
const ACTION_SECONDS := 2.2
var _hip_height := 0.9
var _idle_anim := ""
var _walk_anim := ""
var _moving := false
var _pending_action := ""
var _pending_wait := 0.0
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
	var model_key := ("kid_" + gender) if age_years < KID_MODEL_MAX_AGE else gender
	if model_key != _model_gender:
		_load_model(model_key)
	var age := age_years
	# Boy: 6 yaşta ~%60, 18 yaşta %100
	_target_scale = clampf(0.3 + age * 0.04, 0.35, 1.0)
	if age > 60.0:
		_target_scale -= minf((age - 60.0) * 0.003, 0.06)  # yaşlılıkta hafif kısalma
	# Çocukken kafa gövdeye göre daha büyük
	var growth := clampf((age - 2.0) / 15.0, 0.0, 1.0)
	if _model_gender.begins_with("kid_"):
		# Çocuk modelinin oranları zaten çocuksu
		_head_scale = 1.08
		_leg_scale = 1.0
	else:
		_head_scale = lerpf(1.55, 1.0, growth)
		_leg_scale = lerpf(0.78, 1.0, growth)


func _load_model(model_key: String) -> void:
	if _model:
		_model.queue_free()
	_model_gender = model_key
	_anim = null
	_skeleton = null
	_head_bone = -1
	_spine_bone = -1
	_leg_bones.clear()
	_arm_bones.clear()
	_rig = {}
	_is_mixamo = false
	_idle_anim = ""
	_walk_anim = ""
	var scene: PackedScene = load(MODELS.get(model_key, MODELS.male))
	_model = scene.instantiate()
	_body_root.add_child(_model)

	# Işıksız (unlit) gelen malzemeleri gece-gündüz ışığından etkilenecek hale getir
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m and m.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
				m.roughness = 0.9

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
			if model_key.begins_with("kid_") and (n.contains("leftarm") or n.contains("rightarm")):
				_arm_bones.append(i)
			# Erkek modeli: üst kol "Shoulder.L/R", ön kol "Forearm.L/R"
			if n.begins_with("shoulder.l"):
				_rig["leftarm_"] = i
			elif n.begins_with("shoulder.r"):
				_rig["rightarm_"] = i
			elif n.begins_with("forearm.l"):
				_rig["leftforearm"] = i
			elif n.begins_with("forearm.r"):
				_rig["rightforearm"] = i
			if n.contains("mixamorig"):
				_is_mixamo = true
				for key in ["leftupleg", "rightupleg", "leftleg_", "rightleg_", "leftarm_", "rightarm_",
						"leftforearm", "rightforearm", "lefthand_", "righthand_", "head_", "neck_"]:
					if n.contains(key) and not _rig.has(key):
						_rig[key] = i
				if n.contains("spine_") and not _rig.has("spine"):
					_rig["spine"] = i

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
	_pending_wait = 0.0


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
	# Yürümeye gerek kalmadıysa (zaten oradaysa) bekleyen eylemi kısa süre sonra başlat
	if _pending_action != "" and not _moving:
		_pending_wait += delta
		if _pending_wait > 0.15:
			_start_action(_pending_action)
			_pending_action = ""
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
		if _action_time < ACTION_SECONDS:
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
	if _is_mixamo:
		_animate_mixamo(asleep)
		return
	# Erkek modeli: animasyonu olmayan eylemlerde kolları yönle poza sok
	if not asleep and not _moving and _action_time < ACTION_SECONDS and _action_kind in ["study", "work", "manage", "wash", "social", "date"]:
		var tl := _action_arm_targets(_action_kind, _time)
		if not tl.is_empty():
			_aim_arm("leftarm_", "leftforearm", "", tl[0], tl[1])
			_aim_arm("rightarm_", "rightforearm", "", tl[2], tl[3])
	if _anim == null and _spine_bone >= 0:
		var rest := _skeleton.get_bone_rest(_spine_bone).basis.get_rotation_quaternion()
		var speed := 0.6 if asleep else 1.2
		var amount := 0.015 if asleep else 0.04
		var sway := Quaternion(Vector3(0, 0, 1), sin(_time * speed) * amount) \
			* Quaternion(Vector3(1, 0, 0), sin(_time * speed * 2.0) * amount * 0.5)
		_skeleton.set_bone_pose_rotation(_spine_bone, rest * sway)


## Kodla animasyon (Mixamo iskeleti): yürüme, bekleme ve eylem pozları.
## Bacak/diz/bel/baş X ekseninde döndürülür. Kollar ise karakterin kendi uzayında verilen
## yönlere "nişanlanır" (modelin T-poz/A-poz farkından bağımsız çalışır).
## Karakter uzayı: +Z ileri (yüz), +X karakterin solu, +Y yukarı.
func _animate_mixamo(asleep: bool) -> void:
	var t := _time
	var legs := {"leftupleg": 0.0, "rightupleg": 0.0, "leftleg_": 0.0, "rightleg_": 0.0, "spine": sin(t * 2.4) * 0.02, "head_": sin(t * 0.7) * 0.05}
	# Kol yönleri: [üst kol, ön kol] sol ve sağ için
	var sway := sin(t * 1.3) * 0.05
	var l_up := Vector3(0.18, -1.0, sway)
	var l_lo := Vector3(0.1, -1.0, 0.25)
	var r_up := Vector3(-0.18, -1.0, -sway)
	var r_lo := Vector3(-0.1, -1.0, 0.25)
	if asleep:
		pass
	elif _moving:
		var w := t * 8.0
		legs.leftupleg = sin(w) * 0.5
		legs.rightupleg = -sin(w) * 0.5
		legs.leftleg_ = maxf(0.0, -sin(w)) * 0.7
		legs.rightleg_ = maxf(0.0, sin(w)) * 0.7
		l_up = Vector3(0.15, -1.0, -sin(w) * 0.55)
		r_up = Vector3(-0.15, -1.0, sin(w) * 0.55)
		l_lo = l_up + Vector3(0, 0, 0.45)
		r_lo = r_up + Vector3(0, 0, 0.45)
	elif _action_time < ACTION_SECONDS:
		var fade := clampf(minf(_action_time * 4.0, (ACTION_SECONDS - _action_time) * 4.0), 0.0, 1.0)
		var dl := [l_up, l_lo, r_up, r_lo]
		var tl := _action_arm_targets(_action_kind, t)
		if tl.is_empty():
			tl = dl
		match _action_kind:
			"eat":
				legs.head_ = 0.1
			"study", "work", "manage":
				legs.head_ = 0.35
				legs.spine = 0.12
			"play":
				legs.leftleg_ = absf(sin(t * 7.0)) * 0.5
				legs.rightleg_ = legs.leftleg_
		l_up = dl[0].lerp(tl[0], fade)
		l_lo = dl[1].lerp(tl[1], fade)
		r_up = dl[2].lerp(tl[2], fade)
		r_lo = dl[3].lerp(tl[3], fade)

	_set_bone("leftupleg", Quaternion(Vector3(1, 0, 0), legs.leftupleg))
	_set_bone("rightupleg", Quaternion(Vector3(1, 0, 0), legs.rightupleg))
	_set_bone("leftleg_", Quaternion(Vector3(1, 0, 0), -legs.leftleg_))
	_set_bone("rightleg_", Quaternion(Vector3(1, 0, 0), -legs.rightleg_))
	_set_bone("spine", Quaternion(Vector3(1, 0, 0), legs.spine))
	_set_bone("head_", Quaternion(Vector3(1, 0, 0), legs.head_))
	if not asleep:
		_aim_arm("leftarm_", "leftforearm", "lefthand_", l_up, l_lo)
		_aim_arm("rightarm_", "rightforearm", "righthand_", r_up, r_lo)


## Eylem için kol yönleri [sol üst, sol ön, sağ üst, sağ ön] (karakter uzayı). Yoksa boş.
func _action_arm_targets(kind: String, t: float) -> Array:
	var l_up := Vector3(0.18, -1.0, 0.0)
	var l_lo := Vector3(0.1, -1.0, 0.25)
	match kind:
		"eat":  # Sağ el ağza
			return [l_up, l_lo, Vector3(-0.25, -0.75, 0.6), Vector3(0.35, 0.9 + sin(t * 9.0) * 0.25, 0.2)]
		"wash":  # İki el başın üstünde ovuşturma
			var rub := sin(t * 10.0) * 0.3
			return [Vector3(0.7, 0.7, 0.1), Vector3(-0.8, 0.4 + rub, 0.1), Vector3(-0.7, 0.7, 0.1), Vector3(0.8, 0.4 - rub, 0.1)]
		"study", "work", "manage":  # Eğilip yazma
			var tap := sin(t * 14.0) * 0.12
			return [Vector3(0.25, -0.8, 0.55), Vector3(-0.15, -0.15 + tap, 1.0), Vector3(-0.25, -0.8, 0.55), Vector3(0.15, -0.15 - tap, 1.0)]
		"play":  # Kollar havada
			return [Vector3(0.45, 1.0, 0.1), Vector3(0.3, 1.0, 0.0), Vector3(-0.45, 1.0, 0.1), Vector3(-0.3, 1.0, 0.0)]
		"social", "date":  # Sağ el ile el sallama
			return [l_up, l_lo, Vector3(-1.0, 0.45, 0.1), Vector3(-0.25 + sin(t * 10.0) * 0.45, 1.0, 0.1)]
	return []


## Üst kolu ve ön kolu karakter uzayında verilen yönlere çevir.
func _aim_arm(arm_key: String, fore_key: String, hand_key: String, up_dir: Vector3, lo_dir: Vector3) -> void:
	if not (_rig.has(arm_key) and _rig.has(fore_key)):
		return
	var arm: int = _rig[arm_key]
	var fore: int = _rig[fore_key]
	var hand: int = _rig.get(hand_key, -1)
	if hand < 0:
		var kids := _skeleton.get_bone_children(fore)
		if kids.is_empty():
			return
		hand = kids[0]
	# Karakter uzayından iskelet uzayına
	var to_skel := _skeleton.global_transform.basis.inverse() * global_transform.basis
	var parent := _skeleton.get_bone_parent(arm)
	var parent_g: Transform3D = _skeleton.get_bone_global_pose(parent) if parent >= 0 else Transform3D.IDENTITY
	var arm_g := _aim_one(arm, fore, parent_g, (to_skel * up_dir).normalized())
	_aim_one(fore, hand, arm_g, (to_skel * lo_dir).normalized())


func _aim_one(bone: int, child: int, parent_g: Transform3D, dir: Vector3) -> Transform3D:
	var rest := _skeleton.get_bone_rest(bone)
	var g := parent_g * rest
	var cur := (g.basis * _skeleton.get_bone_rest(child).origin).normalized()
	if cur.length() < 0.001 or dir.length() < 0.001:
		return g
	var q := Quaternion(cur, dir) if cur.dot(dir) > -0.999 else Quaternion(g.basis.x.normalized(), PI)
	var new_basis := Basis(q) * g.basis
	var local := parent_g.basis.inverse() * new_basis
	_skeleton.set_bone_pose_rotation(bone, local.get_rotation_quaternion())
	return Transform3D(new_basis, g.origin)


func _set_bone(key: String, q: Quaternion) -> void:
	if not _rig.has(key):
		return
	var b: int = _rig[key]
	if key == "head_":
		_skeleton.set_bone_pose_scale(b, Vector3.ONE * _head_scale)
	_skeleton.set_bone_pose_rotation(b, _skeleton.get_bone_rest(b).basis.get_rotation_quaternion() * q)


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

