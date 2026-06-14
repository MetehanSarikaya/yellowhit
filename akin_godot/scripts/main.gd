extends Node2D

# ---------- Grid ayarları ----------
const COLS := 11
const ROWS := 19
const CELL := 36
const GTOP := 80
const GBOTTOM := 40
const W := COLS * CELL
const GRID_H := ROWS * CELL
const H := GTOP + GRID_H + GBOTTOM

# ---------- Oyun ayarları ----------
const RANGE := CELL * 2.4
const MAX_TOWERS := 10
const SPEED_NORM := 1.15
const SPEED_SLOW := 0.42
const COOLDOWN_LEN := 170
const EXPLORER_CHANCE := 0.35

# ---------- Renkler ----------
const ENEMY_COL := Color(1.0, 0.42, 0.42)
const ENEMY_DARK := Color(0.70, 0.23, 0.23)
const TOWER_COL := Color(0.31, 0.80, 0.77)
const TOWER_DARK := Color(0.12, 0.55, 0.45)
const CASTLE_COL := Color(1.0, 0.85, 0.24)
const CASTLE_DARK := Color(0.79, 0.65, 0.15)
const PANEL_COL := Color(1, 1, 1, 0.05)
const PANEL_BORDER := Color(1, 1, 1, 0.10)

# ---------- Menü / UI ----------
const START_BTN := Rect2(100, 260, 200, 56)
const RESTART_BTN := Rect2(90, H / 2.0 + 60, 220, 56)

enum Phase { MENU, SETUP, PLAY, OVER }

var phase := Phase.MENU
var fr := 0
var castle_hp := 10
var kills := 0
var wave_num := 0
var cur_wave_size := 0

var castle_cell := Vector2i(-1, -1)
var spawn_cell := Vector2i(-1, -1)
var next_spawn_cell := Vector2i(-1, -1)

var towers: Array = []
var tower_cooldowns: Dictionary = {}

var enemies: Array = []
var shots: Array = []

var astar_normal := AStarGrid2D.new()
var astar_weighted := AStarGrid2D.new()

var spawn_queue := 0
var next_spawn_fr := 0
var wave_cooldown_set := false
var wave_cooldown := 0



var font: Font

var bg_palette := [
	Color(0.047, 0.067, 0.094),
	Color(0.094, 0.055, 0.110),
	Color(0.047, 0.094, 0.078),
	Color(0.102, 0.075, 0.047),
	Color(0.02, 0.02, 0.02),
]
var bg_idx := 0
var current_bg: Color = bg_palette[0]
var swatch_rects: Array = []


func _ready() -> void:
	font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	if font == null:
		font = ThemeDB.fallback_font

	for astar in [astar_normal, astar_weighted]:
		astar.region = Rect2i(0, 0, COLS, ROWS)
		astar.cell_size = Vector2(CELL, CELL)
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
		astar.update()

	swatch_rects.clear()
	for i in range(bg_palette.size()):
		var x := 62.0 + i * (44.0 + 14.0)
		swatch_rects.append(Rect2(x, 410, 44, 44))


func _process(_delta: float) -> void:
	if phase == Phase.PLAY:
		update_game()
	queue_redraw()


# ============================================================
# YARDIMCI FONKSİYONLAR
# ============================================================

func cell_center(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL / 2.0, GTOP + c.y * CELL + CELL / 2.0)

# Haritanın en dış çerçevesindeki tüm hücreleri verir
func get_edge_cells() -> Array:
	var edges: Array = []
	for x in range(COLS):
		edges.append(Vector2i(x, 0))
		edges.append(Vector2i(x, ROWS - 1))
	for y in range(1, ROWS - 1):
		edges.append(Vector2i(0, y))
		edges.append(Vector2i(COLS - 1, y))
	return edges

# Kaleye en uzak kenar hücresini bulur (Oyun başı için)
func farthest_edge(c: Vector2i) -> Vector2i:
	var best := Vector2i(0, 0)
	var bd := -1.0
	for edge in get_edge_cells():
		var d: float = Vector2(edge - c).length()
		if d > bd:
			bd = d
			best = edge
	return best


func pick_next_spawn() -> Vector2i:
	var candidates: Array = []
	for c in get_edge_cells():
		# Kaleye temas eden (komşu) blokları bul (X ve Y farkı 1 veya daha az ise temas ediyordur)
		var is_touching_castle = abs(c.x - castle_cell.x) <= 1 and abs(c.y - castle_cell.y) <= 1
		
		# Kule yoksa, kaleye temas etmiyorsa ve kaleye gidecek bir yolu varsa adaydır
		if not towers.has(c) and not is_touching_castle and not astar_normal.get_id_path(c, castle_cell).is_empty():
			candidates.append(c)
	
	var others: Array = candidates.filter(func(c): return c != spawn_cell)
	var pool: Array = others if others.size() > 0 else candidates
	if pool.is_empty():
		return spawn_cell
	return pool[randi() % pool.size()]

func wave_size_for(n: int) -> int:
	# 1. Dalga: 6 asker | 10. Dalga: 24 asker | 20. Dalga: 44 asker
	return 4 + (n * 2)

func max_hp_for_wave(n: int) -> int:
	# Doğrusal ve adil büyüme: 1. Dalga 4 can, 7. Dalga 14 can, 20. Dalga 35 can.
	return 3 + int(n * 1.8)

func tower_dmg() -> float:
	return 1 + float(wave_num /4.0)
func current_fire_rate() -> int:
	# Hız çok daha pürüzsüz artar ve 25 kerede (saniyede 2.5 atış) kilitlenir.
	return maxi(30, 55 - wave_num )

func recompute_astar() -> void:
	# Kulelerin merkez koordinatlarını döngüye girmeden bir kere hesapla
	var tower_centers: Array = []
	for t in towers:
		tower_centers.append(cell_center(t))
		
	var range_sq := RANGE * RANGE
		
	for x in range(COLS):
		for y in range(ROWS):
			var p := Vector2i(x, y)
			var solid: bool = towers.has(p)
			astar_normal.set_point_solid(p, solid)
			astar_weighted.set_point_solid(p, solid)
			
			var w := 1.0
			var pc := cell_center(p)
			
			# Sadece önceden hesaplanmış merkezleri kullanarak hızlı mesafe kontrolü yap
			for tc in tower_centers:
				if pc.distance_squared_to(tc) <= range_sq:
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
	if phase == Phase.MENU:
		if START_BTN.has_point(pos):
			phase = Phase.SETUP
			return
		for i in range(swatch_rects.size()):
			if swatch_rects[i].has_point(pos):
				bg_idx = i
				current_bg = bg_palette[i]
				return
		return

	if phase == Phase.OVER:
		if RESTART_BTN.has_point(pos):
			reset_game()
		return

	var cx := int(floor(pos.x / CELL))
	var cy := int(floor((pos.y - GTOP) / CELL))
	if cx < 0 or cx >= COLS or cy < 0 or cy >= ROWS:
		return
	var cell := Vector2i(cx, cy)

	if phase == Phase.SETUP:
		castle_cell = cell
		spawn_cell = farthest_edge(castle_cell)
		recompute_astar()
		next_spawn_cell = pick_next_spawn()
		phase = Phase.PLAY
		start_wave()
		return

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

	# Askerler 45 kare arayla gelmeye başlar, oyun sonu 15 kareye kadar sıklaşır.
	var spawn_interval: int = maxi(15, 40 - int(wave_num * 1.3) )
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

	var dmg := tower_dmg()
	var range_sq := RANGE * RANGE # Menzilin karesini bir kere hesapla
	
	for t in towers:
		var cd: float = tower_cooldowns.get(t, 0)
		if cd > 0:
			tower_cooldowns[t] = cd - 1
			continue
			
		var tpos := cell_center(t)
		var target = null
		var bd_sq := INF # En yakın mesafenin karesi
		
		for e in enemies:
			# Karekök almayan, işlemci dostu mesafe hesabı
			var d_sq: float = e.pos.distance_squared_to(tpos) 
			if d_sq <= range_sq and d_sq < bd_sq:
				bd_sq = d_sq
				target = e
				
		if target != null:
			target.hp -= dmg
			target.slow = 80
			shots.append({"from": tpos, "to": target.pos, "age": 0})
			tower_cooldowns[t] = current_fire_rate()

	for s in shots:
		s.age += 1
	shots = shots.filter(func(s): return s.age <= 8)

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
			if castle_hp <= 0:
				phase = Phase.OVER
				Input.vibrate_handheld(250)
			i -= 1
			continue

		# Her dalgada askerlere +0.012 hız eklenir. Kulelerin vurma süresi yavaşça daralır.
		var current_speed: float = SPEED_NORM + (wave_num * 0.012)
		var speed: float = SPEED_SLOW if e.slow > 0 else current_speed

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


# ============================================================
# ÇİZİM
# ============================================================

func _draw() -> void:
	draw_rect(Rect2(0, 0, W, H), current_bg, true)

	if phase == Phase.MENU:
		draw_menu()
		return

	if phase == Phase.SETUP:
		draw_grid()
		draw_centered_text(Vector2(W / 2.0, H / 2.0), "kalenin yerini seç", 12, Color(1, 1, 1, 0.6))
		return

	draw_top_bar()
	draw_grid()

	# Sıradaki giriş noktası (Sapsarı kare)
	if next_spawn_cell != Vector2i(-1, -1):
		var p := Vector2(next_spawn_cell.x * CELL, GTOP + next_spawn_cell.y * CELL)
		# Dalga arası bekleyişteyse daha belirgin yanıp söner, dalga içindeyse saydam durur
		var alpha := 0.6 + 0.3 * sin(fr * 0.1) if (wave_cooldown_set and enemies.is_empty()) else 0.3
		draw_rect(Rect2(p, Vector2(CELL, CELL)), Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, alpha), true)
		draw_rect(Rect2(p, Vector2(CELL, CELL)), CASTLE_COL, false, 2.0)

	for t in towers:
		draw_tower(t)

	draw_castle()

	for e in enemies:
		draw_enemy(e)

	for s in shots:
		var a: float = 1.0 - s.age / 8.0
		draw_line(s.from, s.to, Color(1, 1, 1, a * 0.8), 2.0)

	draw_bottom_badge()

	if wave_cooldown_set and enemies.is_empty():
		draw_centered_text(Vector2(W / 2.0, GTOP + 24), "sıradaki giriş -> sarı kare", 8, Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, 0.85))

	if phase == Phase.OVER:
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6), true)
		draw_centered_text(Vector2(W / 2.0, H / 2.0 - 70), "KALE DÜŞTÜ", 16, Color(1, 1, 1, 1))
		draw_centered_text(Vector2(W / 2.0, H / 2.0 - 30), "dalga %d  öldürülen %d" % [wave_num, kills], 10, Color(1, 1, 1, 0.6))
		draw_button(RESTART_BTN, "TEKRAR OYNA", CASTLE_COL)


func draw_centered_text(pos: Vector2, text: String, size: int, color: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string(font, pos - Vector2(w / 2.0, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func draw_button(rect: Rect2, text: String, accent: Color) -> void:
	draw_rect(rect, Color(accent.r, accent.g, accent.b, 0.18), true)
	draw_rect(rect, accent, false, 2.0)
	draw_centered_text(rect.position + rect.size / 2.0 + Vector2(0, 4), text, 12, Color(1, 1, 1, 1))


func draw_menu() -> void:
	draw_centered_text(Vector2(W / 2.0, 140), "cavac", 40, CASTLE_COL)
	draw_centered_text(Vector2(W / 2.0, 180), "kaleni savun", 9, Color(1, 1, 1, 0.5))

	draw_button(START_BTN, "BAŞLA", TOWER_COL)

	draw_centered_text(Vector2(W / 2.0, 380), "ARKAPLAN", 9, Color(1, 1, 1, 0.4))
	for i in range(bg_palette.size()):
		var r: Rect2 = swatch_rects[i]
		draw_rect(r, bg_palette[i], true)
		var border_col := CASTLE_COL if i == bg_idx else Color(1, 1, 1, 0.15)
		var border_w := 3.0 if i == bg_idx else 1.0
		draw_rect(r, border_col, false, border_w)

	draw_centered_text(Vector2(W / 2.0, 600), "kaleni yerleştir, kule dik,", 9, Color(1, 1, 1, 0.4))
	draw_centered_text(Vector2(W / 2.0, 622), "dalgaları durdur", 9, Color(1, 1, 1, 0.4))


func draw_top_bar() -> void:
	var panel := Rect2(10, 8, W - 20, GTOP - 16)
	draw_rect(panel, PANEL_COL, true)
	draw_rect(panel, PANEL_BORDER, false, 1.0)

	draw_string(font, panel.position + Vector2(12, 26), "DALGA %d" % wave_num, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.85))
	draw_string(font, panel.position + Vector2(12, 48), "x%d  oldurulen %d" % [tower_dmg(), kills], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.45))

	var pip := 8.0
	var gap := 3.0
	var total_w := 10 * pip + 9 * gap
	var start_x := panel.position.x + panel.size.x - total_w - 10
	for i in range(10):
		var x := start_x + i * (pip + gap)
		var col := CASTLE_COL if i < castle_hp else Color(1, 1, 1, 0.12)
		draw_rect(Rect2(Vector2(x, panel.position.y + 14), Vector2(pip, pip)), col, true)
	draw_string(font, Vector2(start_x, panel.position.y + 36), "KALE CANI", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(1, 1, 1, 0.35))


func draw_bottom_badge() -> void:
	var r := Rect2(10, GTOP + GRID_H + 8, 110, 24)
	draw_rect(r, PANEL_COL, true)
	draw_rect(r, PANEL_BORDER, false, 1.0)
	draw_string(font, r.position + Vector2(10, 17), "KULE %d/%d" % [towers.size(), MAX_TOWERS], HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(1, 1, 1, 0.5))


func draw_grid() -> void:
	var col := Color(1, 1, 1, 0.04)
	for cx in range(COLS + 1):
		draw_line(Vector2(cx * CELL, GTOP), Vector2(cx * CELL, GTOP + GRID_H), col, 1.0)
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
	
	# Menzil dairesi (Görseli boğmaması için çok hafif saydam)
	draw_circle(x, RANGE, Color(TOWER_COL.r, TOWER_COL.g, TOWER_COL.b, 0.03))

	# Kule tabanı (Koyu metalik kare kaide)
	draw_rect(Rect2(x - Vector2(12, 12), Vector2(24, 24)), Color(0.15, 0.18, 0.22), true)
	draw_rect(Rect2(x - Vector2(12, 12), Vector2(24, 24)), TOWER_DARK, false, 1.5)

	# Turret Kafası (Zırhlı elmas şekli)
	var core_pts := PackedVector2Array([
		x + Vector2(0, -8),
		x + Vector2(8, 0),
		x + Vector2(0, 8),
		x + Vector2(-8, 0)
	])
	draw_colored_polygon(core_pts, Color(0.2, 0.25, 0.3))
	draw_polyline(core_pts + PackedVector2Array([core_pts[0]]), TOWER_DARK, 1.5)

	# Cooldown Göstergesi (Etrafında dolan neon dolum halkası)
	var cd: float = tower_cooldowns.get(t, 0)
	var ready_ratio := 1.0 - (cd / float(current_fire_rate()))
	
	if ready_ratio > 0.01:
		draw_arc(x, 10, -PI/2.0, -PI/2.0 + ready_ratio * TAU, 24, TOWER_COL, 2.0, true)

	# Merkez Çekirdek Namlusu (Ateş etmeye hazırsa parlar)
	var core_col = TOWER_COL if cd < 8 else TOWER_DARK
	draw_circle(x, 3, core_col)


func draw_castle() -> void:
	var c: Vector2 = cell_center(castle_cell)

	# Alt kaide (Koyu metal/taş taban)
	draw_rect(Rect2(c.x - 14, c.y + 6, 28, 8), Color(0.25, 0.28, 0.32), true)
	draw_rect(Rect2(c.x - 10, c.y + 2, 20, 4), Color(0.35, 0.38, 0.42), true)

	# Dış çekirdek (Koyu sarı elmas)
	var core_pts := PackedVector2Array([
		Vector2(c.x, c.y - 16),
		Vector2(c.x + 10, c.y - 2),
		Vector2(c.x, c.y + 8),
		Vector2(c.x - 10, c.y - 2)
	])
	draw_colored_polygon(core_pts, CASTLE_DARK)

	# İç çekirdek (Parlayan sarı merkez)
	var core_inner := PackedVector2Array([
		Vector2(c.x, c.y - 10),
		Vector2(c.x + 5, c.y - 2),
		Vector2(c.x, c.y + 4),
		Vector2(c.x - 5, c.y - 2)
	])
	draw_colored_polygon(core_inner, CASTLE_COL)

	# Çekirdeğin etrafında nabız gibi atan enerji kalkanı
	var pulse := 1.0 + 0.15 * sin(fr * 0.1)
	draw_arc(c + Vector2(0, -2), 16 * pulse, 0, TAU, 24, Color(CASTLE_COL.r, CASTLE_COL.g, CASTLE_COL.b, 0.6), 1.5, true)


func draw_enemy(e: Dictionary) -> void:
	var p: Vector2 = e.pos
	var col := CASTLE_COL if e.explorer else ENEMY_COL
	var dark_col := CASTLE_DARK if e.explorer else ENEMY_DARK

	# 1. Zırhlı Gövde (Performans dostu 4 noktalı poligon)
	var body_pts := PackedVector2Array([
		p + Vector2(0, -10),
		p + Vector2(10, 0),
		p + Vector2(0, 10),
		p + Vector2(-10, 0),
		p + Vector2(0, -10) # Çizgiyi kapatmak için başa dön
	])
	
	# İçini koyu renkle doldur, dışına neon hat çek
	draw_colored_polygon(body_pts, dark_col)
	draw_polyline(body_pts, col, 1.5)

	# 2. Parlayan Çekirdek Göz
	draw_circle(p, 3.5, col)

	# 3. Can Barı (Kompakt, ince ve şık)
	var frac: float = float(e.hp) / float(e.maxhp)
	var bar_w := 16.0
	var bar_pos := p + Vector2(-bar_w / 2.0, -16)
	
	# Siyah arka plan ve can oranına göre dolan renk
	draw_rect(Rect2(bar_pos, Vector2(bar_w, 3)), Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(bar_pos, Vector2(bar_w * frac, 3)), col, true)

	# 4. Yavaşlatma Efekti (Ağır yuvarlak yerine hafif genişleyen elmas)
	if e.slow > 0:
		var pulse := 1.0 + 0.2 * sin(fr * 0.3)
		var aura_pts := PackedVector2Array([
			p + Vector2(0, -14 * pulse),
			p + Vector2(14 * pulse, 0),
			p + Vector2(0, 14 * pulse),
			p + Vector2(-14 * pulse, 0),
			p + Vector2(0, -14 * pulse)
		])
		draw_polyline(aura_pts, Color(TOWER_COL.r, TOWER_COL.g, TOWER_COL.b, 0.7), 1.0)
