extends Node2D

const TILE_SIZE = 32
const LEVEL_SIZES = [
	Vector2(30, 30),
	Vector2(35, 35),
	Vector2(40, 40),
	Vector2(45, 45),
	Vector2(50, 50),
]

const LEVEL_ROOM_COUNTS = [5, 7, 9, 12, 15]
const MIN_ROOM_DIMENSION = 5
const MAX_ROOM_DIMENSION = 8

enum Tile {Wall, Door, Floor, Ladder, Stone}

# Current Level -----------
var level_num = 0
var map = []
var rooms = []
var level_size

# Node refs ---------------
onready var tile_map = $TileMap
onready var player = $Player # $ references node by path?

# Game State --------------
var player_tile
var score = 0

# Called when the node enters the scene tree for the first time.
func _ready():
	OS.set_window_size(Vector2(1280, 720))
	randomize()
	build_level()
	
func build_level():
	# Start with a blank map
	rooms.clear()
	map.clear()
	tile_map.clear()
	
	level_size = LEVEL_SIZES[level_num]
	for x in range(level_size.y):
		map.append([])
		for y in range(level_size.y):
			map[x].append(Tile.Stone)
			tile_map.set_cell(x, y, Tile.Stone)
	
	# Creating corridors and walls?
	var free_regions = [Rect2(Vector2(2, 2), level_size - Vector2(4, 4))]
	var num_rooms = LEVEL_ROOM_COUNTS[level_num]
	for i in range(num_rooms):
		add_room(free_regions)
		if free_regions.empty():
			break

	connect_rooms()

func connect_rooms():
	# Build an AStar graph of the area where we can add corridors

	var stone_graph = AStar.new()
	var point_id = 0
	for x in range(level_size.x):
		for y in range(level_size.y):
			if map[x][y] == Tile.Stone:
				stone_graph.add_point(point_id, Vector3(x, y, 0))

				# Connect to left if also stone
				if x > 0 && map[x - 1][y] == Tile.Stone:
					var left_point = stone_graph.get_closest_point(Vector3(x - 1, y, 0))
					stone_graph.connect_points(point_id, left_point)

				# Connect to above if also stone
				if y > 0 && map[x][y -1] == Tile.Stone:
					var above_point = stone_graph.get_closest_point(Vector3(x, y - 1, 0))
					stone_graph.connect_points(point_id, above_point)

				point_id += 1

	# Build an AStar graph of room connections
	var room_graph = AStar.new()
	point_id = 0
	for room in rooms:
		var room_center = room.position + room.size / 2
		room_graph.add_point(point_id, Vector3(room_center.x, room_center.y, 0))
		point_id += 1

	# Add random connections until everything is connected
	while !is_everything_connected(room_graph):
		add_random_connection(stone_graph, room_graph)

# Attempts to loop round in a path, if it can't, something isn't connected
func is_everything_connected(graph):
	var points = graph.get_points()
	var start = points.pop_back()
	for point in points:
		var path = graph.get_point_path(start, point)
		if !path:
			return false

	return true

func add_random_connection(stone_graph, room_graph):
	# Pick rooms to connect
	var start_room_id = get_least_connected_point(room_graph)
	var end_room_id = get_nearest_unconnected_point(room_graph, start_room_id)

	# Pick door locations
	var start_position = pick_random_door_location(rooms[start_room_id])
	var end_position = pick_random_door_location(rooms[end_room_id])

	# Find a path to connect the doors to each other
	var closest_start_point = stone_graph.get_closest_point(start_position)
	var closest_end_point = stone_graph.get_closest_point(end_position)

	var path = stone_graph.get_point_path(closest_start_point, closest_end_point)
	assert(path) # Shouldn't fail, but if it does we want to know

	for position in path:
		set_tile(position.x, position.y, Tile.Floor)

	room_graph.connect_points(start_room_id, end_room_id)

# Helper func
func get_least_connected_point(graph):
	var point_ids = graph.get_points()

	var least
	var tied_for_least = []

	for point in point_ids:
		var count = graph.get_point_connections(point).size()
		if !least || count < least:
			least = count
			tied_for_least = [point]
		elif count == least:
			tied_for_least.append(point)

	return tied_for_least[randi() % tied_for_least.size()]

# Helper func 
func get_nearest_unconnected_point(graph, target_point):
	var target_position = graph.get_point_position(target_point)
	var point_ids = graph.get_points()

	var nearest
	var tied_for_nearest = []

	for point in point_ids:
		if point == target_point: # Don't connect room to itself
			continue

		# Already path connecting the 2 rooms
		var path = graph.get_point_path(point, target_point)
		if path:
			continue

		var dist = (graph.get_point_position(point) - target_position).length()
		if !nearest || dist < nearest:
			nearest = dist
			tied_for_nearest = [point]
		elif dist == nearest:
			tied_for_nearest.append(point)

	return tied_for_nearest[randi() % tied_for_nearest.size()]

func pick_random_door_location(room):
	var options = []

	# Top and bottom walls
	for x in range(room.position.x + 1, room.end.x - 2):
		options.append(Vector3(x, room.position.y, 0))
		options.append(Vector3(x, room.end.y - 1, 0))

	# Left and right walls - skipping top and bottom row (like when adding wall tiles)
	for y in range(room.position.y + 1, room.end.y - 2):
		options.append(Vector3(room.position.x, y, 0))
		options.append(Vector3(room.end.x - 1, y, 0))

	return options[randi() % options.size()]

func add_room(free_regions):
	var region = free_regions[randi() % free_regions.size()]

	# How big to make the room
	var size_x = MIN_ROOM_DIMENSION
	if region.size.x > MIN_ROOM_DIMENSION:
		size_x += randi() % int(region.size.x - MIN_ROOM_DIMENSION)

	var size_y = MIN_ROOM_DIMENSION
	if region.size.y > MIN_ROOM_DIMENSION:
		size_y += randi() % int(region.size.y - MIN_ROOM_DIMENSION)

	size_x = min(size_x, MAX_ROOM_DIMENSION)
	size_y = min(size_y, MAX_ROOM_DIMENSION)

	# Position the room within the free space
	var start_x = region.position.x
	if region.size.x > size_x:
		start_x += randi() % int(region.size.x - size_x)

	var start_y = region.position.y
	if region.size.y > size_y:
		start_y += randi() % int(region.size.y - size_y)

	var room = Rect2(start_x, start_y, size_x, size_y)
	rooms.append(room)

	# Set tiles in the map for this room, starting with top & bot walls
	for x in range(start_x, start_x + size_x):
		set_tile(x, start_y, Tile.Wall)
		set_tile(x, start_y + size_y - 1, Tile.Wall)

	for y in range(start_y + 1, start_y + size_y - 1):
		set_tile(start_x, y, Tile.Wall)
		set_tile(start_x + size_x - 1, y, Tile.Wall)

		# Iterate over floor
		for x in range(start_x + 1, start_x + size_x - 1):
			set_tile(x, y, Tile.Floor)

	# Update free regions list
	cut_regions(free_regions, room)

func cut_regions(free_regions, region_to_remove):
	var removal_queue = []
	var addition_queue = []

	for region in free_regions:
		if region.intersects(region_to_remove):
			removal_queue.append(region)

			var leftover_left = region_to_remove.position.x - region.position.x - 1
			var leftover_right = region.end.x - region_to_remove.end.x - 1
			var leftover_above = region_to_remove.position.y - region.position.y - 1
			var leftover_below = region.end.y - region_to_remove.end.y - 1

			# Each side of the room that has enough space for a room, add a new 'region'
			if leftover_left >= MIN_ROOM_DIMENSION:
				addition_queue.append(Rect2(region.position, Vector2(leftover_left, region.size.y)))
			if leftover_right >= MIN_ROOM_DIMENSION:
				addition_queue.append(Rect2(Vector2(region_to_remove.end.x + 1, region.position.y), Vector2(leftover_right, region.size.y)))
			if leftover_above >= MIN_ROOM_DIMENSION:
				addition_queue.append(Rect2(region.position, Vector2(region.size.x, leftover_above)))
			if leftover_below >= MIN_ROOM_DIMENSION:
				addition_queue.append(Rect2(Vector2(region.position.x, region_to_remove.end.y + 1), Vector2(region.size.x, leftover_below)))

	for region in removal_queue:
		free_regions.erase(region)

	for region in addition_queue:
		free_regions.append(region)

func set_tile(x, y, type):
	map[x][y] = type
	tile_map.set_cell(x, y, type)

