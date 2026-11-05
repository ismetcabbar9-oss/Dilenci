extends Node3D
## Ev: GameState.home_level'e göre odaları kurar (Sketchfab modelleri, bkz. CREDITS.md).
## Seviye 0: tek odalı "Low Poly Room". Seviye 1+: "Low Poly Isometric Rooms" paketinden
## odalar yan yana dizilir. Karakterin eyleme göre gideceği noktaları verir.

const SMALL_ROOM := "res://assets/models/rooms/room_small.glb"
const HOUSE := "res://assets/models/rooms/rooms_house.glb"
# Paket içindeki oda düğümleri
const HOUSE_ROOMS := {
	"cinema": "Room1", "study": "Room2", "living": "Room3", "kitchen": "Room4",
	"bedroom": "Room5", "bathroom": "Room6", "gym": "Room7",
}
const ROOM_NAMES := {
	"small": "Oda", "kitchen": "Mutfak", "living": "Oturma odası", "bedroom": "Yatak odası",
	"bathroom": "Banyo", "study": "Çalışma odası", "gym": "Spor odası", "cinema": "Hobi odası",
	"garden": "Bahçe", "school": "Okul", "office": "İşyeri",
}
# Hangi eylem hangi odada yapılır (ilk bulunan oda kullanılır)
const ACTION_ROOMS := {
	"idle": ["living", "small"],
	"eat": ["kitchen", "small"],
	"sleep": ["bedroom", "small"],
	"wash": ["bathroom", "small"],
	"study": ["study", "living", "small"],
	"work": ["study", "living", "small"],
	"manage": ["study", "living", "small"],
	"play": ["gym", "living", "small"],
	"social": ["cinema", "living", "small"],
	"date": ["cinema", "living", "small"],
}
const PLACES := {
	"school": {"path": "res://assets/models/places/school.glb", "x": -40.0, "yaw": 0.0, "name": "Okul", "spot": Vector3(0.3, 0, 1.0)},
	"office": {"path": "res://assets/models/places/office.glb", "x": -52.0, "yaw": PI, "name": "İşyeri", "spot": Vector3(-0.7, 0, 1.4)},
}
# Bahçede sergilenen lüks varlıklar: model, sahnedeki yuva (bahçe merkezine göre), en büyük boyut
const LUXURY_MODELS := {
	"car": {"path": "res://assets/models/luxury/cars.glb", "slot": Vector3(-1.1, 0, 0.75), "size": 1.25, "keep": "Sedan"},
	"boat": {"path": "res://assets/models/luxury/boat.glb", "slot": Vector3(0.05, 0, 0.8), "size": 1.1, "paint": "boat"},
	"summer_house": {"path": "res://assets/models/luxury/summer_house.glb", "slot": Vector3(-1.1, 0, -0.85), "size": 1.2, "paint": "house"},
	"yacht": {"path": "res://assets/models/luxury/yacht.glb", "slot": Vector3(1.15, 0, 0.75), "size": 1.25},
	"jet": {"path": "res://assets/models/luxury/jet.glb", "slot": Vector3(0.05, 0, -0.75), "size": 1.2},
	"island": {"path": "res://assets/models/luxury/island.glb", "slot": Vector3(1.05, 0.55, -0.8), "scale": 0.024},
}
const ROOM_SPACING := 3.75
const FLOOR_Y := 0.0

## [{id, center: Vector3, size: Vector3, bed: Vector3 (yoksa INF)}]
var rooms: Array = []
var built_level := -1
var built_key := ""
var places := {}          # id -> {center: Vector3}
var _instance: Node3D
var _garden: Node3D


func build(level: int, luxury: Array = []) -> void:
	var key := "%d|%s" % [level, ",".join(luxury)]
	if key == built_key:
		return
	built_key = key
	built_level = level
	if _instance:
		_instance.queue_free()
		_instance = null
	if _garden:
		_garden.queue_free()
		_garden = null
	rooms.clear()
	var ids: Array = GameState.HOMES[level].rooms
	if ids.has("small"):
		_build_small()
	else:
		_build_house(ids)
	if not luxury.is_empty():
		_build_garden(luxury)
	if places.is_empty():
		_build_places()


## Okul ve işyeri: evden uzakta, karakter oraya "gider".
func _build_places() -> void:
	for id in PLACES:
		var p: Dictionary = PLACES[id]
		var n: Node3D = load(p.path).instantiate()
		add_child(n)
		n.rotation.y = p.yaw
		var box := _aabb(n)
		n.scale = Vector3.ONE * (3.9 / maxf(maxf(box.size.x, box.size.z), 0.01))
		box = _aabb(n)
		n.global_position += Vector3(p.x - box.get_center().x, FLOOR_Y - box.position.y, -box.get_center().z)
		places[id] = {"id": id, "center": Vector3(p.x, FLOOR_Y, 0.0)}


## Bahçe: çimen, çit ve sahip olunan lüks varlıkların minyatürleri.
func _build_garden(luxury: Array) -> void:
	_garden = Node3D.new()
	add_child(_garden)
	var last: Dictionary = rooms.back()
	var c := Vector3(last.center.x + ROOM_SPACING, FLOOR_Y, last.center.z)
	_garden_box(Vector3(3.6, 0.12, 3.6), c + Vector3(0, -0.06, 0), Color(0.42, 0.7, 0.32))
	for i in 7:  # arka ve sağ çit
		_garden_box(Vector3(0.08, 0.6, 0.08), c + Vector3(-1.75 + i * 0.58, 0.3, -1.75), Color(0.95, 0.95, 0.9))
		_garden_box(Vector3(0.08, 0.6, 0.08), c + Vector3(1.75, 0.3, -1.75 + i * 0.58), Color(0.95, 0.95, 0.9))
	_garden_box(Vector3(3.6, 0.07, 0.05), c + Vector3(0, 0.45, -1.75), Color(0.95, 0.95, 0.9))
	_garden_box(Vector3(0.05, 0.07, 3.6), c + Vector3(1.75, 0.45, 0), Color(0.95, 0.95, 0.9))
	for id in luxury:
		if not LUXURY_MODELS.has(id):
			continue
		var d: Dictionary = LUXURY_MODELS[id]
		var n: Node3D = load(d.path).instantiate()
		_garden.add_child(n)
		if d.has("keep"):
			for child in n.find_children("SHTV_Prefab_*", "Node3D", true, false):
				child.visible = String(child.name).contains(d.keep)
		_fix_vertex_colors(n)
		if d.has("paint"):
			_paint(n, d.paint)
		if d.has("scale"):
			# Kutusu yanıltıcı modeller (ör. ada: uzak bulutlar/şelale): orijine göre yerleştir
			n.scale = Vector3.ONE * float(d.scale)
			n.rotation.y = 0.6
			n.global_position = c + d.slot
			continue
		var box := _aabb(n)
		n.scale = Vector3.ONE * (float(d.size) / maxf(maxf(box.size.x, box.size.z), 0.01))
		n.rotation.y = 0.6
		box = _aabb(n)
		var target: Vector3 = c + d.slot
		n.global_position += Vector3(target.x - box.get_center().x, target.y + FLOOR_Y - box.position.y, target.z - box.get_center().z)
	rooms.append({"id": "garden", "center": c, "size": Vector3(3.6, 1, 3.6), "bed": Vector3.INF, "bed_yaw": 0.0})


func _garden_box(size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.95
	mi.material_override = mat
	mi.position = pos
	_garden.add_child(mi)


## Dokusuz (beyaz) gelen modelleri parça boyutlarına göre renklendir.
static func _paint(root: Node3D, style: String) -> void:
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	if style == "boat":
		for mi in meshes:
			if String(mi.name).begins_with("Plane"):
				mi.visible = false  # modelle gelen büyük zemin düzlemi
			else:
				mi.material_override = _mat(Color(0.86, 0.22, 0.2), 0.4)
		return
	# Yazlık: parçaları boyut ve yüksekliğe göre sınıfla
	var total := AABB()
	var first := true
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		total = b if first else total.merge(b)
		first = false
	var wall := _mat(Color(0.97, 0.94, 0.87), 0.9)
	var floor_m := _mat(Color(0.78, 0.58, 0.38), 0.8)
	var base := _mat(Color(0.86, 0.8, 0.68), 0.95)
	var glass := _mat(Color(0.45, 0.7, 0.9), 0.2)
	var metal := _mat(Color(0.32, 0.33, 0.36), 0.6)
	var leaf := _mat(Color(0.3, 0.68, 0.3), 0.9)
	var trunk := _mat(Color(0.55, 0.38, 0.22), 0.9)
	for mi in meshes:
		var b: AABB = mi.global_transform * mi.mesh.get_aabb()
		var rel_y := (b.position.y - total.position.y) / maxf(total.size.y, 0.001)
		var big := maxf(b.size.x, b.size.z) / maxf(maxf(total.size.x, total.size.z), 0.001)
		var flat := b.size.y < 0.06 * maxf(b.size.x, b.size.z)
		var m: Material = wall
		if rel_y < 0.08 and big > 0.6:
			m = base
		elif flat and big > 0.25:
			m = floor_m
		elif flat:
			m = glass
		elif big < 0.08 and b.size.y > 2.0 * maxf(b.size.x, b.size.z):
			m = trunk
		elif big < 0.08:
			m = metal
		elif big < 0.2 and rel_y > 0.45:
			m = leaf
		mi.material_override = m


static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	return m


## Köşe rengi (vertex color) kullanan modellerde rengi görünür yap.
static func _fix_vertex_colors(root: Node) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		for si in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(si) if mesh is ArrayMesh else []
			if arrays.is_empty():
				continue
			var col = arrays[Mesh.ARRAY_COLOR]
			if col == null or col.size() == 0:
				continue
			var m := mesh.surface_get_material(si) as BaseMaterial3D
			if m:
				m.vertex_color_use_as_albedo = true


func place_spot(id: String) -> Vector3:
	if not places.has(id):
		return Vector3.ZERO
	return places[id].center + PLACES[id].spot


func _build_small() -> void:
	_instance = load(SMALL_ROOM).instantiate()
	add_child(_instance)
	# Model santimetre ölçeğinde gelir (~320 birim); ~3.4 m genişliğe ölçekle.
	var box := _aabb(_instance)
	_instance.scale = Vector3.ONE * (3.4 / maxf(box.size.x, 0.01))
	box = _aabb(_instance)
	# Zemini y=0'a, merkezi orijine al.
	_instance.global_position += Vector3(-box.get_center().x, FLOOR_Y - (box.position.y + box.size.y * 0.077), -box.get_center().z)
	box = _aabb(_instance)
	rooms.append({
		"id": "small",
		"center": Vector3(box.get_center().x, FLOOR_Y, box.get_center().z),
		"size": box.size,
		# Yatak sağ duvarda, arka duvardan öne uzanıyor (ayak ucu öne bakar)
		"bed": Vector3(box.end.x - 0.62, FLOOR_Y + 0.42, box.position.z + 1.95),
		"bed_yaw": 0.0,
	})


func _build_house(ids: Array) -> void:
	_instance = load(HOUSE).instantiate()
	add_child(_instance)
	var all_rooms := {}
	for n in _instance.find_children("Room*", "Node3D", true, false):
		all_rooms[n.name] = n
	# Kullanılmayan odaları gizle, kullanılanları yan yana diz
	var used := []
	for id in ids:
		used.append(HOUSE_ROOMS[id])
	for name in all_rooms:
		all_rooms[name].visible = used.has(name)
	var count := ids.size()
	for i in count:
		var node: Node3D = all_rooms[HOUSE_ROOMS[ids[i]]]
		var box := _aabb(node)
		var target_center := Vector3((i - (count - 1) / 2.0) * ROOM_SPACING, 0, 0)
		var delta := Vector3(target_center.x - box.get_center().x, FLOOR_Y - (box.position.y + 0.1), target_center.z - box.get_center().z)
		node.global_position += delta
		box = _aabb(node)
		var room := {"id": ids[i], "center": Vector3(box.get_center().x, FLOOR_Y, box.get_center().z), "size": box.size, "bed": Vector3.INF, "bed_yaw": 0.0}
		var bed := node.find_child("Bed*", true, false) as Node3D
		if bed:
			var bb := _aabb(bed)
			if bb.size.x > bb.size.z:
				# Yatak yan duruyor: baş sağ duvarda (+x), ayaklar solda
				room.bed = Vector3(bb.position.x + 0.25, bb.end.y - 0.32, bb.get_center().z + 0.3)
				room.bed_yaw = -PI / 2.0
			else:
				# Baş arka duvarda (-z), ayaklar önde
				room.bed = Vector3(bb.get_center().x, bb.end.y - 0.2, bb.end.z - 0.2)
		rooms.append(room)


func get_room(id: String) -> Dictionary:
	for r in rooms:
		if r.id == id:
			return r
	return rooms[0] if not rooms.is_empty() else {}


func room_for_action(kind: String) -> Dictionary:
	for id in ACTION_ROOMS.get(kind, ["living", "small"]):
		for r in rooms:
			if r.id == id:
				return r
	return rooms[0] if not rooms.is_empty() else {}


func room_index(id: String) -> int:
	for i in rooms.size():
		if rooms[i].id == id:
			return i
	return 0


## Odada durulacak nokta (açık taraf: +x ve +z, duvarlar -z tarafında).
# Odaya göre karakterin ana durma noktası (eşyalardan uzak)
const ROOM_STAND := {
	"small": Vector3(-0.3, 0, 0.9), "living": Vector3(-1.0, 0, 1.3), "kitchen": Vector3(0.0, 0, 1.0),
	"bedroom": Vector3(-0.9, 0, 1.2), "bathroom": Vector3(-0.6, 0, 1.2), "study": Vector3(-0.5, 0, 1.2),
	"gym": Vector3(0.2, 0, 1.2), "cinema": Vector3(-0.4, 0, 1.3),
}


func stand_spot(room: Dictionary, slot: int = 0) -> Vector3:
	if slot == 0:
		return room.center + ROOM_STAND.get(room.id, Vector3(0, 0, 1.2))
	# Odanın ön kısmı (kameraya yakın, genelde eşyasız)
	var offsets := [Vector3(0.2, 0, 1.25), Vector3(1.0, 0, 1.15), Vector3(-0.6, 0, 1.3),
		Vector3(0.35, 0, 1.55), Vector3(-1.2, 0, 1.0), Vector3(0.6, 0, 1.45)]
	var o: Vector3 = offsets[slot % offsets.size()]
	return room.center + o


static func _aabb(root: Node) -> AABB:
	var result := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not (mi as MeshInstance3D).is_visible_in_tree():
			continue
		var b: AABB = mi.global_transform * (mi as MeshInstance3D).mesh.get_aabb()
		result = b if first else result.merge(b)
		first = false
	if root is MeshInstance3D:
		var b2: AABB = root.global_transform * root.mesh.get_aabb()
		result = b2 if first else result.merge(b2)
	return result
