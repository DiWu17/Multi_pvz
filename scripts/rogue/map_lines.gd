extends Node2D
class_name MapLines

## 地图连线绘制节点 - 使用虚线绘制路径连接

var map: RogueMap = null

## 虚线参数
const DASH_LENGTH: float = 8.0        ## 每段虚线长度
const GAP_LENGTH: float = 5.0         ## 虚线间隔长度
const LINE_WIDTH: float = 2.0         ## 线宽
const LINE_COLOR: Color = Color(0.296, 0.264, 0.202, 1.0)  ## 线条颜色
const HIGHLIGHT_COLOR: Color = Color(1.0, 0.85, 0.4, 0.9)  ## 高亮颜色（已走过的路径）

func _draw() -> void:
	if map == null:
		return
	for edge in map.edges:
		if edge[0].y >= map.grid.size() or edge[1].y >= map.grid.size():
			continue
		if edge[0].x >= map.grid[edge[0].y].size() or edge[1].x >= map.grid[edge[1].y].size():
			continue
		var from_node: RogueMapNode = map.grid[edge[0].y][edge[0].x]
		var to_node: RogueMapNode = map.grid[edge[1].y][edge[1].x]
		if from_node == null or to_node == null:
			continue
		var from_pos: Vector2 = map.get_node_center(from_node)
		var to_pos: Vector2 = map.get_node_center(to_node)
		# 判断是否为已走过的路径
		var color: Color = LINE_COLOR
		if _is_visited_edge(from_node, to_node):
			color = HIGHLIGHT_COLOR
		_draw_dashed_line(from_pos, to_pos, color, LINE_WIDTH)

func _draw_dashed_line(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var direction: Vector2 = (to - from)
	var total_length: float = direction.length()
	if total_length < 0.01:
		return
	var dir_normalized: Vector2 = direction / total_length
	var segment_length: float = DASH_LENGTH + GAP_LENGTH
	var distance: float = 0.0

	while distance < total_length:
		var dash_start: Vector2 = from + dir_normalized * distance
		var dash_end_dist: float = minf(distance + DASH_LENGTH, total_length)
		var dash_end: Vector2 = from + dir_normalized * dash_end_dist
		draw_line(dash_start, dash_end, color, width, true)
		distance += segment_length

func _is_visited_edge(from_node: RogueMapNode, to_node: RogueMapNode) -> bool:
	## 只有两端节点都被玩家实际访问过才算走过的路径
	return from_node.visited and to_node.visited
