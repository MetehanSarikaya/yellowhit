extends Node2D

# ---------- Grid ayarları ----------
const COLS := 10
const ROWS := 18
const CELL := 48
const GTOP := 96
const W := COLS * CELL
const H := GTOP + ROWS * CELL

# ---------- Oyun ayarları ----------
const RANGE := CELL * 2.4
const MAX_TOWERS := 10
const FIRE_RATE := 70          # frame cinsinden ateş aralığı
const SPEED_NORM := 1.4        # px/frame
const SPEED_SLOW := 0.5
const COOLDOWN_LEN := 170       # dalgalar arası "inşa" penceresi (frame)
const EXPLORER_CHANCE := 0.35

# ---------- Renkler ----------
const ENEMY_COL := Color(1.0, 0.42, 0.42)
const ENEMY_DARK := Color(0.70, 0.23, 0.23)
const TOWER_COL := Color(0.31, 0.80, 0.77)
const TOWER_DARK := Color(0.12, 0.55, 0.45)
const CASTLE_COL := Color(1.0, 0.85, 0.24)
const CASTLE_DARK := Color(0.79, 0.65, 0.15)
const BG_COL := Color(0.047, 0.067, 0.094)

enum Phase { SETUP, PLAY, OVER }

var phase := Phase.SETUP
var fr := 0
var castle_hp := 10
var kills := 0
var wave_num := 0
var cur_wave_size := 0

var castle_cell := Vector2i(-1, -1)
var spawn_cell := Vector2i(-1, -1)
var next_spawn_cell := Vector2i(-1, -1)

var towers: Array = []                 # Vector2i listesi
var tower_cooldowns: Dictionary = {}   # Vector2i -> int

var enemies: Array = []                # Dictionary listesi
var shots: Array = []                  # {from, to, age}

var astar_normal := AStarGrid2D.new()
var astar_weighted := AStarGrid2D.new()

var spawn_queue := 0
var next_spawn_fr := 0
var wave_cooldown_set := false
var wave_cooldown := 0

var corners := [
	Vector2i(0, 0),
	Vector2i(COLS - 1, 0),
	Vector2i(0, ROWS - 1),
	Vector2i(COLS - 1, ROWS - 1),
]

var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font

	for astar in [astar_normal, astar_weighted]:
		astar.region = Rect2i(0, 0, COLS, ROWS)
		astar.cell_size = Vector2(CELL, CELL)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.update()


func _process(_delta: float) -> void:
	if phase == Phase.PLAY:
		update_game()
	queue_redraw()


# ============================================================
# YARDIMCI FONKSİYONLAR
# ============================================================

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, GTOP + c.y * CELL + CELL / 2.0)


func farthest_corner(c: Vector2i) -> Vector2i:
	var best: Vector2i = corners[0]
	var bd := -1.0
	for co in corners:
		var d: float = Vector2(co - c).length()
		if d > bd:
			bd = d
			best = co
	return best


func pick_next_spawn() -> Vector2i:
	var candidates: Array = []
	for c in corners:
		if not astar_normal.get_id_path(c, castle_cell).is_empty():
			candidates.append(c)
	var others: Array = candidates.filter(func(c): return c != spawn_cell)
	var pool: Array = others if others.size() > 0 else candidates
	if pool.is_empty():
		return spawn_cell
	return pool[randi() % pool.size()]


func wave_size_for(n: int) -> int:
	var s := 1
	for i in range(1, n):
		s = int(ceil(s * 1.5)) + 1
	return s


func max_hp_for_wave(n: int) -> int:
	return min(8, 1 + int(n / 2.0))


func tower_dmg() -> int:
	return 1 + int(kills / 8.0)


func recompute_astar() -> void:
	for x in range(COLS):
		for y in range(ROWS):
			var p := Vector2i(x, y)
			var solid: bool = towers.has(p)
			astar_normal.set_point_solid(p, solid)
			astar_weighted.set_point_solid(p, solid)
			var w := 1.0
			var pc := cell_center(p)
			for t in towers:
				if pc.distance_to(cell_center(t)) <= RANGE:
					w += 2.0
			astar_weighted.set_point_weight_scale(p, min(w, 7.0))


func set_enemy_path(e: Dictionary) -> void:
	var astar := astar_weighted if e.explorer else astar_normal
	var p: Array = astar.get_id_path(e.cell, castle_cell)
	if p.size() <= 1:
		p = astar_normal.get_id_path(e.cell, castle_cell)
	e.path = p
	if p.size() <= 1:
		e.reached = true
		return
	e.path_idx = 1
	e.target_pos = cell_center(p[1]) + e.offset


# ============================================================
# GİRDİ
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var pressed := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = true
	if not pressed:
		return
	handle_tap(pos)


func handle_tap(pos: Vector2) -> void:
	if phase == Phase.OVER:
		reset_game()
		return

	var cx := int(floor(pos.x / CELL))
	var cy := int(floor((pos.y - GTOP) / CELL))
	if cx < 0 or cx >= COLS or cy < 0 or cy >= ROWS:
		return
	var cell := Vector2i(cx, cy)

	if phase == Phase.SETUP:
		castle_cell = cell
		spawn_cell = farthest_corner(castle_cell)
		recompute_astar()
		next_spawn_cell = pick_next_spawn()
		phase = Phase.PLAY
		start_wave()
		return

	# Var olan kuleye dokunma -> kaldır
	var idx := towers.find(cell)
	if idx >= 0:
		towers.remove_at(idx)
		tower_cooldowns.erase(cell)
		recompute_astar()
		for e in enemies:
			set_enemy_path(e)
		if astar_normal.get_id_path(next_spawn_cell, castle_cell).is_empty():
			next_spawn_cell = pick_next_spawn()
		return

	if cell == castle_cell or cell == spawn_cell or cell == next_spawn_cell:
		return
	if towers.size() >= MAX_TOWERS:
		return

	towers.append(cell)
	recompute_astar()
	var p1 := astar_normal.get_id_path(spawn_cell, castle_cell)
	var p2 := astar_normal.get_id_path(next_spawn_cell, castle_cell)
	if p1.is_empty() or p2.is_empty():
		towers.remove_at(towers.size() - 1)
		recompute_astar()
		return

	for e in enemies:
		set_enemy_path(e)


# ============================================================
# OYUN DÖNGÜSÜ
# ============================================================

func reset_game() -> void:
	phase = Phase.SETUP
	fr = 0
	castle_hp = 10
	kills = 0
	wave_num = 0
	cur_wave_size = 0
	castle_cell = Vector2i(-1, -1)
	spawn_cell = Vector2i(-1, -1)
	next_spawn_cell = Vector2i(-1, -1)
	towers.clear()
	tower_cooldowns.clear()
	enemies.clear()
	shots.clear()
	spawn_queue = 0
	wave_cooldown_set = false
	recompute_astar()


func start_wave() -> void:
	wave_num += 1
	if next_spawn_cell != Vector2i(-1, -1):
		spawn_cell = next_spawn_cell
	cur_wave_size = wave_size_for(wave_num)
	spawn_queue = cur_wave_size
	next_spawn_fr = fr + 30
	play_sfx($SfxWave)


func spawn_enemy() -> void:
	var offset := Vector2(randf_range(-10, 10), randf_range(-10, 10))
	var mh := max_hp_for_wave(wave_num)
	var e := {
		"pos": cell_center(spawn_cell) + offset,
		"cell": spawn_cell,
		"offset": offset,
		"hp": mh,
		"maxhp": mh,
		"slow": 0,
		"reached": false,
		"explorer": randf() < EXPLORER_CHANCE,
		"path": [],
		"path_idx": 0,
		"target_pos": Vector2.ZERO,
	}
	set_enemy_path(e)
	enemies.append(e)


func update_game() -> void:
	fr += 1

	var spawn_interval := max(6, 24 - wave_num * 2)
	if spawn_queue > 0 and fr >= next_spawn_fr:
		spawn_enemy()
		spawn_queue -= 1
		next_spawn_fr = fr + spawn_interval

	if spawn_queue == 0 and enemies.is_empty() and not wave_cooldown_set:
		wave_cooldown = fr + COOLDOWN_LEN
		wave_cooldown_set = true
		next_spawn_cell = pick_next_spawn()

	if wave_cooldown_set and fr >= wave_cooldown:
		wave_cooldown_set = false
		start_wave()

	# Kuleler ateş ediyor
	var dmg := tower_dmg()
	for t in towers:
		var cd: int = tower_cooldowns.get(t, 0)
		if cd > 0:
			tower_cooldowns[t] = cd - 1
			continue
		var tpos := cell_center(t)
		var target = null
		var bd := INF
		for e in enemies:
			var d: float = e.pos.distance_to(tpos)
			if d <= RANGE and d < bd:
				bd = d
				target = e
		if target != null:
			target.hp -= dmg
			target.slow = 80
			shots.append({"from": tpos, "to": target.pos, "age": 0})
			tower_cooldowns[t] = FIRE_RATE
			play_sfx($SfxShoot)

	for s in shots:
		s.age += 1
	shots = shots.filter(func(s): return s.age <= 8)

	# Askerler hareket ediyor
	var i := enemies.size() - 1
	while i >= 0:
		var e: Dictionary = enemies[i]
		if e.hp <= 0:
			kills += 1
			enemies.remove_at(i)
			i -= 1
			continue
		if e.slow > 0:
			e.slow -= 1
		if e.reached:
			castle_hp -= 1
			enemies.remove_at(i)
			Input.vibrate_handheld(80)
			play_sfx($SfxHit)
			if castle_hp <= 0:
				phase = Phase.OVER
				Input.vibrate_handheld(250)
			i -= 1
			continue

		var speed := SPEED_SLOW if e.slow > 0 else SPEED_NORM
		var to_target: Vector2 = e.target_pos - e.pos
		var d: float = to_target.length()
		if d < speed * 1.3:
			e.pos = e.target_pos
			e.cell = e.path[e.path_idx]
			if e.cell == castle_cell:
				e.reached = true
			else:
				e.path_idx += 1
				if e.path_idx >= e.path.size():
					e.reached = true
				else:
					e.target_pos = cell_center(e.path[e.path_idx]) + e.offset
		else:
			e.pos += to_target.normalized() * speed
		i -= 1


func play_sfx(player: AudioStreamPlayer) -> void:
	if player.stream != null:
		player.play()


# ============================================================
# ÇİZİM
# ============================================================

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), BG_COL, true)

	if phase == Phase.SETUP:
		draw_grid()
		draw_centered_text(Vector2(W / 2.0, H / 2.0), "kalenin yerini seç", 22, Color(1, 1, 1, 0.6))
		return

	draw_top_bar()
	draw_grid()

	# giriş noktaları
	draw_cell_outline(spawn_cell, Color(ENEMY_COL.r, ENEMY_COL.g, ENEMY_COL.b, 0.35), 2.0)
	if next_spawn_cell != spawn_cell:
		var pulse := 0.4 + 0.3 * sin(fr * 0.15)
		draw_cell_outline(next_spawn_cell, Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, pulse), 2.5)

	for t in towers:
		draw_tower(t)

	draw_castle()

	for e in enemies:
		draw_enemy(e)

	for s in shots:
		var a: float = 1.0 - s.age / 8.0
		draw_line(s.from, s.to, Color(1, 1, 1, a * 0.8), 2.0)

	draw_string(font, Vector2(20, H - 14), "kule: %d/%d" % [towers.size(), MAX_TOWERS], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 1, 1, 0.3))

	if wave_cooldown_set and enemies.is_empty():
		draw_centered_text(Vector2(W / 2.0, GTOP + 50), "sarı kare = sıradaki giriş, hazırlan!", 16, Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, 0.8))

	if phase == Phase.OVER:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.55), true)
		draw_centered_text(Vector2(W / 2.0, H / 2.0 - 24), "kale düştü", 28, Color(1, 1, 1, 1))
		draw_centered_text(Vector2(W / 2.0, H / 2.0 + 14), "ulaştığın dalga: %d — öldürülen: %d" % [wave_num, kills], 18, Color(1, 1, 1, 0.7))
		draw_centered_text(Vector2(W / 2.0, H / 2.0 + 46), "tekrar oynamak için dokun", 18, Color(1, 1, 1, 0.6))


func draw_centered_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_top_bar() -> void:
	draw_rect(Rect2(20, 28, W - 40, 12), Color(1, 1, 1, 0.1), true)
	var hp_color := CASTLE_COL if castle_hp > 3 else ENEMY_COL
	draw_rect(Rect2(20, 28, (W - 40) * (castle_hp / 10.0), 12), hp_color, true)
	draw_string(font, Vector2(20, 64), "kale canı", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.45))

	var right1 := "öldürülen: %d  güç:x%d" % [kills, tower_dmg()]
	var right2 := "dalga %d (%d)" % [wave_num, cur_wave_size]
	var w1: float = font.get_string_size(right1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	var w2: float = font.get_string_size(right2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, Vector2(W - 20 - w1, 52), right1, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.45))
	draw_string(font, Vector2(W - 20 - w2, 76), right2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.45))


func draw_grid() -> void:
	var col := Color(1, 1, 1, 0.04)
	for cx in range(COLS + 1):
		draw_line(Vector2(cx * CELL, GTOP), Vector2(cx * CELL, H), col, 1.0)
	for cy in range(ROWS + 1):
		draw_line(Vector2(0, GTOP + cy * CELL), Vector2(W, GTOP + cy * CELL), col, 1.0)


func draw_cell_outline(cell: Vector2i, color: Color, width: float) -> void:
	if cell == Vector2i(-1, -1):
		return
	var p := Vector2(cell.x * CELL, GTOP + cell.y * CELL)
	draw_rect(Rect2(p + Vector2(2, 2), Vector2(CELL - 4, CELL - 4)), color, false, width)


func draw_ring(center: Vector2, radius: float, color: Color, width: float) -> void:
	draw_arc(center, radius, 0, TAU, 32, color, width, true)


func draw_tower(t: Vector2i) -> void:
	var x: Vector2 = cell_center(t)
	draw_circle(x, RANGE, Color(TOWER_COL.r, TOWER_COL.g, TOWER_COL.b, 0.05))
	draw_rect(Rect2(x - Vector2(17, 17), Vector2(34, 34)), Color(TOWER_COL.r, TOWER_COL.g, TOWER_COL.b, 0.18), true)
	draw_rect(Rect2(x - Vector2(17, 17), Vector2(34, 34)), TOWER_COL, false, 2.0)
	draw_circle(x, 7, TOWER_COL)

	var cd: int = tower_cooldowns.get(t, 0)
	var ang := -PI / 2.0 + (cd / float(FIRE_RATE)) * TAU
	var col2 := Color(1, 1, 1, 1) if cd < 8 else TOWER_DARK
	draw_line(x, x + Vector2(cos(ang), sin(ang)) * 12, col2, 2.5)


func draw_castle() -> void:
	var x: Vector2 = cell_center(castle_cell)
	var s := CELL * 0.62

	draw_rect(Rect2(x - Vector2(s, s * 0.6), Vector2(s * 2, s * 1.6)), Color(0.667, 0.663, 0.627), true)
	for i in range(-1, 2):
		draw_rect(Rect2(x + Vector2(-s + i * s * 0.7 - 5, -s * 0.6 - 12), Vector2(s * 0.5, 12)), Color(0.549, 0.545, 0.510), true)

	draw_rect(Rect2(x + Vector2(-2, -s * 1.5), Vector2(4, s * 0.9)), CASTLE_COL, true)
	var pts := PackedVector2Array([
		x + Vector2(2, -s * 1.5),
		x + Vector2(2, -s * 1.1),
		x + Vector2(22, -s * 1.3),
	])
	draw_colored_polygon(pts, CASTLE_COL)

	draw_rect(Rect2(x - Vector2(s, s * 0.6), Vector2(s * 2, s * 1.6)), CASTLE_DARK, false, 2.0)


func draw_enemy(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	if e.explorer:
		draw_ring(p, 16, Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, 0.45), 2.0)

	draw_circle(p + Vector2(0, 6), 11, ENEMY_COL)
	draw_circle(p + Vector2(0, -6), 9, Color(1, 0.88, 0.74))
	draw_circle(p + Vector2(0, -10), 9, ENEMY_DARK)
	draw_circle(p + Vector2(-3, -6), 1.5, Color(0.17, 0.17, 0.17))
	draw_circle(p + Vector2(3, -6), 1.5, Color(0.17, 0.17, 0.17))

	var frac: float = float(e.hp) / float(e.maxhp)
	draw_rect(Rect2(p + Vector2(-18, -30), Vector2(36, 5)), Color(1, 1, 1, 0.15), true)
	draw_rect(Rect2(p + Vector2(-18, -30), Vector2(36 * frac, 5)), ENEMY_COL, true)

	if e.slow > 0:
		draw_ring(p, 18, Color(TOWER_COL.r, TOWER_COL.g, TOWER_COL.b, 0.5), 1.5)
