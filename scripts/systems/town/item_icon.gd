extends Control
## Tiny hand-drawn item icons (no textures): fish, shells, sea glass, driftwood, stones, bottle, treats...
## Everything is a flat toy shape with an ink outline.

const INK := Color("6b4a3a")
var kind := "dot"
var c1 := Color.WHITE
var c2 := Color.WHITE
var gold := false
var _t := 0.0

func _init(k := "dot", a := Color.WHITE, b := Color.WHITE, g := false) -> void:
	kind = k; c1 = a; c2 = b; gold = g
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

func _ready() -> void:
	set_process(gold)

func _process(dt: float) -> void:
	_t += dt
	queue_redraw()

func _poly(pts: PackedVector2Array, fill: Color, w := 2.0) -> void:
	draw_colored_polygon(pts, fill)
	var loop := pts.duplicate()
	loop.append(pts[0])
	draw_polyline(loop, INK, w, true)

func _ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n:
		var a := TAU * k / n
		var p := Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)
		pts.append(c + p)
	return pts

func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	match kind:
		"fish":
			var rx := s * 0.3; var ry := s * 0.2
			_poly(PackedVector2Array([c + Vector2(-rx * 0.8, 0), c + Vector2(-rx - s * 0.2, -s * 0.17), c + Vector2(-rx - s * 0.2, s * 0.17)]), c2)
			_poly(PackedVector2Array([c + Vector2(-rx * 0.2, -ry * 0.8), c + Vector2(rx * 0.1, -ry - s * 0.12), c + Vector2(rx * 0.35, -ry * 0.7)]), c2)
			_poly(_ellipse(c + Vector2(s * 0.04, 0), rx, ry), c1)
			draw_circle(c + Vector2(s * 0.22, -s * 0.04), s * 0.04, INK)
			draw_arc(c + Vector2(s * 0.1, 0), ry * 0.7, -0.9, 0.9, 8, Color(INK.r, INK.g, INK.b, 0.35), 2.0, true)
		"shell":
			var pts := PackedVector2Array()
			var base := c + Vector2(0, s * 0.3)
			pts.append(base)
			for k in 11:
				var a := lerpf(-2.65, -0.49, k / 10.0)
				var r := s * (0.46 if k % 2 == 0 else 0.4)
				pts.append(base + Vector2(cos(a), sin(a)) * r)
			_poly(pts, c1)
			for k in 5:
				var a := lerpf(-2.4, -0.74, k / 4.0)
				draw_line(base, base + Vector2(cos(a), sin(a)) * s * 0.36, c2, 2.0, true)
			draw_circle(base, s * 0.05, c2)
		"glass":
			var pts2 := PackedVector2Array()
			for k in 14:
				var a := TAU * k / 14.0
				var r := s * (0.3 + 0.04 * sin(a * 3.0 + 1.0))
				pts2.append(c + Vector2(cos(a) * r, sin(a) * r * 0.85))
			_poly(pts2, Color(c1.r, c1.g, c1.b, 0.9))
			draw_circle(c + Vector2(-s * 0.1, -s * 0.1), s * 0.06, Color(1, 1, 1, 0.8))
		"wood":
			var a0 := c + Vector2(-s * 0.3, s * 0.12)
			var b0 := c + Vector2(s * 0.3, -s * 0.12)
			draw_line(a0, b0, INK, s * 0.26, true)
			draw_circle(a0, s * 0.13, INK); draw_circle(b0, s * 0.13, INK)
			draw_line(a0, b0, c1, s * 0.2, true)
			draw_circle(a0, s * 0.1, c1); draw_circle(b0, s * 0.1, c1)
			draw_line(c + Vector2(-s * 0.1, s * 0.05), c + Vector2(-s * 0.02, -s * 0.2), INK, s * 0.12, true)
			draw_line(c + Vector2(-s * 0.1, s * 0.05), c + Vector2(-s * 0.02, -s * 0.2), c1, s * 0.07, true)
		"star":
			var pts3 := PackedVector2Array()
			for k in 10:
				var a := -PI / 2 + TAU * k / 10.0
				var r := s * (0.42 if k % 2 == 0 else 0.19)
				pts3.append(c + Vector2(cos(a), sin(a)) * r)
			_poly(pts3, c1)
		"moon":
			_poly(_ellipse(c + Vector2(0, s * 0.05), s * 0.3, s * 0.26), c1)
			var sp := PackedVector2Array()
			for k in 30:
				var a := k * 0.3
				var r := s * 0.03 + k * s * 0.007
				sp.append(c + Vector2(0, s * 0.05) + Vector2(cos(a), sin(a)) * r)
			draw_polyline(sp, c2, 2.0, true)
		"bottle":
			_poly(_ellipse(c + Vector2(-s * 0.06, s * 0.05), s * 0.3, s * 0.17, -0.5), Color(c1.r, c1.g, c1.b, 0.95))
			draw_line(c + Vector2(s * 0.12, -s * 0.12), c + Vector2(s * 0.28, -s * 0.28), INK, s * 0.14, true)
			draw_line(c + Vector2(s * 0.12, -s * 0.12), c + Vector2(s * 0.28, -s * 0.28), c1, s * 0.09, true)
			draw_circle(c + Vector2(s * 0.32, -s * 0.32), s * 0.07, Color("c98a5a"))
			draw_line(c + Vector2(-s * 0.2, s * 0.14), c + Vector2(s * 0.02, -s * 0.02), Color("fff6ea"), 3.0, true)
		"flower":
			for k in 5:
				var a := TAU * k / 5.0 - PI / 2
				_poly(_ellipse(c + Vector2(cos(a), sin(a)) * s * 0.19, s * 0.15, s * 0.15), c1)
			_poly(_ellipse(c, s * 0.1, s * 0.1), Color("f2c14e"))
		"treat":
			_poly(_ellipse(c, s * 0.34, s * 0.3), c1)
			for p in [Vector2(-0.1, -0.08), Vector2(0.12, -0.02), Vector2(-0.02, 0.13)]:
				draw_circle(c + p * s, s * 0.04, c2)
		"rod":
			var a1 := c + Vector2(-s * 0.32, s * 0.34)
			var b1 := c + Vector2(s * 0.3, -s * 0.34)
			draw_line(a1, b1, INK, 8.0, true)
			draw_line(a1, b1, c1, 4.0, true)
			draw_line(b1, b1 + Vector2(0, s * 0.45), INK, 1.5, true)
			draw_arc(b1 + Vector2(-s * 0.05, s * 0.45), s * 0.06, 0.0, PI, 8, INK, 2.0, true)
			_poly(_ellipse(c + Vector2(-s * 0.14, s * 0.14), s * 0.09, s * 0.09), c2)
		"scarf":
			draw_arc(c + Vector2(0, -s * 0.05), s * 0.26, 0.2, PI - 0.2, 16, INK, s * 0.2, true)
			draw_arc(c + Vector2(0, -s * 0.05), s * 0.26, 0.2, PI - 0.2, 16, c1, s * 0.14, true)
			_poly(PackedVector2Array([c + Vector2(s * 0.1, s * 0.12), c + Vector2(s * 0.24, s * 0.12), c + Vector2(s * 0.24, s * 0.4), c + Vector2(s * 0.1, s * 0.34)]), c1)
		"cap":
			var dome := PackedVector2Array()
			for k in 13:
				var a := PI + PI * k / 12.0
				dome.append(c + Vector2(cos(a) * s * 0.32, sin(a) * s * 0.3 + s * 0.12))
			_poly(dome, c1)
			_poly(_ellipse(c + Vector2(s * 0.14, s * 0.14), s * 0.28, s * 0.07), c2)
		"paint":
			_poly(_ellipse(c + Vector2(0, s * 0.06), s * 0.3, s * 0.25), c1)
			draw_circle(c + Vector2(-s * 0.12, -s * 0.02), s * 0.05, Color(1, 1, 1, 0.7))
			draw_circle(c + Vector2(s * 0.12, s * 0.12), s * 0.04, c2)
		_:
			_poly(_ellipse(c, s * 0.3, s * 0.3), c1)
	if gold:
		var a := 0.5 + 0.5 * sin(_t * 4.0)
		var sp2 := c + Vector2(s * 0.3, -s * 0.3)
		var k := s * (0.12 + 0.05 * a)
		draw_line(sp2 - Vector2(k, 0), sp2 + Vector2(k, 0), Color("fff3c0"), 3.0, true)
		draw_line(sp2 - Vector2(0, k), sp2 + Vector2(0, k), Color("fff3c0"), 3.0, true)
