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
const ROOM_SPACING := 3.75
const FLOOR_Y := 0.0

## [{id, center: Vector3, size: Vector3, bed: Vector3 (yoksa INF)}]
var rooms: Array = []
var built_level := -1
var _instance: Node3D


func build(level: int) -> void:
	if level == built_level:
		return
	built_level = level
	if _instance:
		_instance.queue_free()
		_instance = null
	rooms.clear()
	var ids: Array = GameState.HOMES[level].rooms
	if ids.has("small"):
		_build_small()
	else:
		_build_house(ids)


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
