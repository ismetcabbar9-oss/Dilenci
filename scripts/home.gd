extends Node3D
## Ev: GameState.home_level'e göre odaları kurar. Odalar kodla kurulur (renkli zemin + iki duvar),
## mobilyalar Quaternius "Ultimate Home Interior" paketinden (CC0). Karakterin eyleme göre gideceği
## noktaları ve yatağın yerini verir.

const FURNITURE := "res://assets/models/interior/%s.fbx"
const ROOM_SIZE := 3.6
const WALL_H := 2.6
## Oda tasarımları: duvar/zemin rengi ve mobilyalar [model, x, z, dönüş°, en büyük boyut(m), y, etiket]
## Koordinatlar oda merkezine göre; arka duvar z=-1.8, sol duvar x=-1.8; kamera önden (+z) bakar.
const ROOM_DESIGNS := {
	"small": {"wall": Color(0.98, 0.55, 0.66), "floor": Color(0.86, 0.66, 0.46), "items": [
		["Bed_Single", -1.15, -0.8, 0, 2.0, 0, "bed"], ["NightStand_1", -0.2, -1.5, 0, 0.55],
		["Drawer_1", 0.95, -1.5, 0, 1.25], ["Window_Large1", 0.95, -1.76, 0, 1.2, 1.15],
		["Carpet_Round", 0.35, 0.35, 0, 1.5], ["Houseplant_1", 1.5, -0.6, 0, 0.6],
		["Table_RoundSmall", -1.25, 0.95, 0, 0.75], ["Chair_1", -0.75, 1.0, -90, 0.85],
		["Light_Floor1", -1.55, 0.2, 0, 1.6]]},
	"kitchen": {"wall": Color(0.5, 0.85, 0.7), "floor": Color(0.95, 0.92, 0.86), "items": [
		["Kitchen_Cabinet1", -1.4, -1.45, 0, 0.75], ["Kitchen_Oven", -0.68, -1.45, 0, 0.75],
		["Kitchen_Sink", 0.04, -1.45, 0, 0.75], ["Kitchen_3Drawers", 0.76, -1.45, 0, 0.75],
		["Kitchen_Fridge", 1.45, -1.42, 0, 1.9], ["Window_Small1", 0.04, -1.76, 0, 0.9, 1.35],
		["Table_RoundSmall", 0.2, 0.55, 0, 1.0], ["Chair_2", -0.45, 0.55, 90, 0.85], ["Chair_2", 0.85, 0.55, -90, 0.85],
		["Houseplant_3", -1.5, 1.2, 0, 0.7]]},
	"living": {"wall": Color(1.0, 0.74, 0.45), "floor": Color(0.8, 0.6, 0.42), "items": [
		["Carpet_2", 0.1, -0.3, 0, 2.6], ["Couch_Large1", 0.1, -1.35, 0, 2.3],
		["Table_RoundSmall", 0.1, -0.25, 0, 0.9], ["Fireplace", -1.55, -0.1, 90, 1.5],
		["Light_Floor1", 1.5, -1.5, 0, 1.7], ["Houseplant_2", 1.5, -0.7, 0, 0.8],
		["Window_Large1", 0.1, -1.76, 0, 1.5, 1.35], ["Couch_Small1", 1.3, 0.6, -90, 1.1]]},
	"bedroom": {"wall": Color(0.66, 0.6, 0.95), "floor": Color(0.86, 0.7, 0.52), "items": [
		["Carpet_1", 0.0, 0.2, 0, 2.2], ["Bed_King", -0.1, -0.75, 0, 2.3, 0, "bed"],
		["NightStand_1", -1.3, -1.5, 0, 0.55], ["NightStand_1", 1.1, -1.5, 0, 0.55],
		["Drawer_2", -1.55, 0.8, 90, 1.4], ["Window_Large1", -1.76, 0.8, 90, 1.2, 1.35],
		["Houseplant_5", 1.5, 0.9, 0, 0.7]]},
	"bathroom": {"wall": Color(0.5, 0.78, 0.98), "floor": Color(0.96, 0.97, 1.0), "items": [
		["Bathroom_Bathtub", -0.95, -1.2, 0, 1.7], ["Bathroom_Toilet", 0.55, -1.5, 0, 0.75],
		["Bathroom_Sink", 1.35, -1.55, 0, 0.75], ["Bathroom_Mirror1", 1.35, -1.76, 0, 0.6, 1.25],
		["Bathroom_WashingMachine", -1.5, 0.6, 90, 0.7], ["Bathroom_Towel", -1.76, 1.25, 90, 0.5, 1.0],
		["Carpet_Round", 0.4, 0.3, 0, 1.1], ["Houseplant_3", 1.5, 1.2, 0, 0.6]]},
	"study": {"wall": Color(0.6, 0.86, 0.5), "floor": Color(0.82, 0.64, 0.45), "items": [
		["Bookshelf", -1.55, -0.6, 90, 1.9], ["Table_RoundLarge", 0.3, -1.25, 0, 1.6],
		["Chair_1", 0.3, -0.6, 180, 0.9], ["Light_Desk", 0.85, -1.4, 0, 0.45, 0.78],
		["Shelf_1", 1.45, -1.5, 0, 1.5], ["Window_Small1", 0.3, -1.76, 0, 0.9, 1.45],
		["Houseplant_5", -1.4, 1.2, 0, 0.7], ["Carpet_1", 0.3, 0.3, 0, 1.8]]},
	"gym": {"wall": Color(1.0, 0.82, 0.3), "floor": Color(0.62, 0.8, 0.95), "items": [
		["Carpet_2", 0.0, 0.0, 0, 2.8], ["Couch_Small1", -1.45, -0.2, 90, 1.1],
		["Shelf_Small1", 0.6, -1.76, 0, 1.2, 1.3], ["Stool", 0.4, -0.2, 0, 0.5], ["Stool", 0.9, 0.3, 0, 0.5],
		["Houseplant_2", 1.5, -1.5, 0, 0.8], ["Light_Floor1", -1.5, -1.5, 0, 1.6]]},
	"cinema": {"wall": Color(0.36, 0.64, 0.68), "floor": Color(0.62, 0.42, 0.3), "items": [
		["Bookshelf", -0.9, -1.55, 0, 1.9], ["Bookshelf", 0.2, -1.55, 0, 1.9], ["Fireplace", -1.55, 0.3, 90, 1.5],
		["Couch_Medium1", 0.9, 0.4, -90, 1.7], ["Carpet_Round", 0.0, 0.3, 0, 1.6],
		["Light_Chandelier", 0.0, 0.2, 0, 0.8, 1.7], ["Houseplant_1", 1.5, -1.5, 0, 0.7]]},
}
const ROOM_NAMES := {
	"small": "Oda", "kitchen": "Mutfak", "living": "Oturma odası", "bedroom": "Yatak odası",
	"bathroom": "Banyo", "study": "Çalışma odası", "gym": "Oyun odası", "cinema": "Kütüphane",
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
	_build_rooms(ids)
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


## Odaları yan yana kurar: renkli zemin, arka ve sol duvar (süpürgelik ve korniş), mobilyalar.
func _build_rooms(ids: Array) -> void:
	_instance = Node3D.new()
	add_child(_instance)
	var count := ids.size()
	for i in count:
		var id: String = ids[i]
		var d: Dictionary = ROOM_DESIGNS.get(id, ROOM_DESIGNS.small)
		var c := Vector3((i - (count - 1) / 2.0) * ROOM_SPACING, FLOOR_Y, 0.0)
		var h := ROOM_SIZE / 2.0
		var wall: Color = d.wall
		_room_box(Vector3(ROOM_SIZE, 0.14, ROOM_SIZE), c + Vector3(0, -0.07, 0), d.floor, 0.85)
		_room_box(Vector3(ROOM_SIZE, WALL_H, 0.14), c + Vector3(0, WALL_H / 2.0, -h - 0.07), wall, 0.95)
		_room_box(Vector3(0.14, WALL_H, ROOM_SIZE + 0.14), c + Vector3(-h - 0.07, WALL_H / 2.0, -0.07), wall.darkened(0.08), 0.95)
		# Süpürgelik ve üst korniş (beyaz şeritler)
		_room_box(Vector3(ROOM_SIZE, 0.14, 0.05), c + Vector3(0, 0.07, -h + 0.02), Color(1, 1, 1), 0.6)
		_room_box(Vector3(0.05, 0.14, ROOM_SIZE), c + Vector3(-h + 0.02, 0.07, 0), Color(1, 1, 1), 0.6)
		_room_box(Vector3(ROOM_SIZE + 0.16, 0.1, 0.2), c + Vector3(0, WALL_H, -h - 0.07), wall.lightened(0.35), 0.6)
		_room_box(Vector3(0.2, 0.1, ROOM_SIZE + 0.2), c + Vector3(-h - 0.07, WALL_H, -0.07), wall.lightened(0.35), 0.6)
		var room := {"id": id, "center": c, "size": Vector3(ROOM_SIZE, WALL_H, ROOM_SIZE), "bed": Vector3.INF, "bed_yaw": 0.0}
		for it in d.items:
			var n := _place_furniture(it, c)
			if it.size() > 6 and it[6] == "bed" and n:
				var bb := _aabb(n)
				# Yatak: baş arka duvarda (-z), ayaklar önde; karakter yatağın üstüne uzanır
				room.bed = Vector3(bb.get_center().x, bb.end.y - 0.22, bb.end.z - 0.3)
				room.bed_yaw = 0.0
		rooms.append(room)


## Mobilyayı yerleştir: en büyük boyutuna ölçekle, zemine (veya verilen yüksekliğe) oturt.
func _place_furniture(it: Array, c: Vector3) -> Node3D:
	var path := FURNITURE % it[0]
	if not ResourceLoader.exists(path):
		return null
	var holder := Node3D.new()
	_instance.add_child(holder)
	var m: Node3D = load(path).instantiate()
	holder.add_child(m)
	holder.rotation.y = deg_to_rad(float(it[3]))
	var box := _aabb(holder)
	var k := float(it[4]) / maxf(maxf(box.size.x, box.size.z), maxf(box.size.y, 0.001))
	holder.scale = Vector3.ONE * k
	box = _aabb(holder)
	var y := float(it[5]) if it.size() > 5 else 0.0
	holder.global_position += Vector3(c.x + float(it[1]) - box.get_center().x, FLOOR_Y + y - box.position.y, c.z + float(it[2]) - box.get_center().z)
	return holder


func _room_box(size: Vector3, pos: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _mat(color, rough)
	mi.position = pos
	_instance.add_child(mi)


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
	"small": Vector3(0.35, 0, 0.45), "living": Vector3(-0.35, 0, 0.75), "kitchen": Vector3(-0.6, 0, -0.65),
	"bedroom": Vector3(0.7, 0, 0.75), "bathroom": Vector3(0.4, 0, 0.3), "study": Vector3(0.95, 0, -0.45),
	"gym": Vector3(0.0, 0, 0.45), "cinema": Vector3(-0.2, 0, 0.6),
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
