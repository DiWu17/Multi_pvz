extends CanvasLayer
## 调试控制台 - 按 ` 键呼出/隐藏
## 支持输入命令执行游戏调试操作

const MAX_LOG_LINES := 200

var _panel: PanelContainer
var _output_label: RichTextLabel
var _input_field: LineEdit
var _is_visible := false
var _command_history: Array[String] = []
var _history_index := -1

## 已注册的命令 {命令名: {callable, description}}
var _commands: Dictionary = {}


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_register_builtin_commands()
	_set_console_visible(false)


func _build_ui() -> void:
	# 半透明背景面板
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 0.5
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = 0
	_panel.offset_bottom = 0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.1, 0.88)
	style.border_color = Color(0.3, 0.8, 0.3, 0.6)
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	_panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 标题
	var title := Label.new()
	title.text = "--- 调试控制台 (输入 help 查看命令) ---"
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# 输出区域
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_output_label = RichTextLabel.new()
	_output_label.bbcode_enabled = true
	_output_label.scroll_following = true
	_output_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_output_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	_output_label.add_theme_font_size_override("normal_font_size", 14)
	_output_label.selection_enabled = true

	vbox.add_child(_output_label)

	# 输入框
	var hbox := HBoxContainer.new()

	var prompt := Label.new()
	prompt.text = "> "
	prompt.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	hbox.add_child(prompt)

	_input_field = LineEdit.new()
	_input_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_field.placeholder_text = "输入命令..."
	_input_field.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_input_field.add_theme_color_override("font_placeholder_color", Color(0.5, 0.5, 0.5))
	var input_style := StyleBoxFlat.new()
	input_style.bg_color = Color(0.1, 0.1, 0.15, 0.9)
	input_style.border_color = Color(0.3, 0.7, 0.3, 0.5)
	input_style.border_width_bottom = 1
	input_style.content_margin_left = 4
	input_style.content_margin_right = 4
	_input_field.add_theme_stylebox_override("normal", input_style)
	_input_field.text_submitted.connect(_on_command_submitted)
	hbox.add_child(_input_field)

	vbox.add_child(hbox)
	_panel.add_child(vbox)
	add_child(_panel)


func _unhandled_input(event: InputEvent) -> void:
	# 多人模式下客户端禁用控制台
	if NetworkManager.is_multiplayer and not multiplayer.is_server():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT or event.physical_keycode == KEY_QUOTELEFT:
			_toggle_console()
			get_viewport().set_input_as_handled()
			return
	# 控制台打开时处理历史导航
	if _is_visible and event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP:
			_navigate_history(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN:
			_navigate_history(1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			_set_console_visible(false)
			get_viewport().set_input_as_handled()


func _toggle_console() -> void:
	_set_console_visible(not _is_visible)


func _set_console_visible(show: bool) -> void:
	_is_visible = show
	_panel.visible = show
	if show:
		_input_field.grab_focus()
		_input_field.clear()


func _navigate_history(direction: int) -> void:
	if _command_history.is_empty():
		return
	_history_index = clampi(_history_index + direction, 0, _command_history.size() - 1)
	_input_field.text = _command_history[_history_index]
	_input_field.caret_column = _input_field.text.length()


func _on_command_submitted(text: String) -> void:
	var cmd_text := text.strip_edges()
	if cmd_text.is_empty():
		return

	# 清除输入框中残留的 ` 字符（防止切换时残留）
	_input_field.clear()

	# 记入历史
	_command_history.push_front(cmd_text)
	if _command_history.size() > 50:
		_command_history.resize(50)
	_history_index = -1

	print_line("[color=lime]> " + cmd_text + "[/color]")

	# 解析命令
	var parts := cmd_text.split(" ", false)
	if parts.is_empty():
		return
	var cmd_name := parts[0].to_lower()
	var args := parts.slice(1)

	if _commands.has(cmd_name):
		var entry: Dictionary = _commands[cmd_name]
		var callable_fn: Callable = entry["callable"]
		callable_fn.call(args)
	else:
		print_line("[color=red]未知命令: " + cmd_name + "  输入 help 查看可用命令[/color]")


## 向控制台输出一行（支持 BBCode）
func print_line(bbcode_text: String) -> void:
	_output_label.append_text(bbcode_text + "\n")
	# 限制行数
	while _output_label.get_line_count() > MAX_LOG_LINES:
		_output_label.remove_paragraph(0)


## 注册自定义命令
func register_command(cmd_name: String, callable_fn: Callable, description: String = "") -> void:
	_commands[cmd_name.to_lower()] = {
		"callable": callable_fn,
		"description": description
	}


## ========== 内置命令 ==========

func _register_builtin_commands() -> void:
	register_command("help", _cmd_help, "显示所有可用命令")
	register_command("clear", _cmd_clear, "清空控制台输出")
	register_command("fps", _cmd_fps, "显示/隐藏 FPS")
	register_command("speed", _cmd_speed, "设置游戏速度 (speed <倍数>)")
	register_command("sun", _cmd_sun, "设置阳光数量 (sun <数量>)")
	register_command("coin", _cmd_coin, "设置金币数量 (coin <数量>)")
	register_command("pause", _cmd_pause, "暂停/恢复游戏")
	register_command("scene", _cmd_scene, "显示当前场景路径")
	register_command("tree", _cmd_tree, "显示场景树概要")
	register_command("eval", _cmd_eval, "执行 GDScript 表达式 (eval <表达式>)")
	register_command("quit", _cmd_quit, "退出游戏")
	register_command("fullscreen", _cmd_fullscreen, "切换全屏/窗口模式")
	register_command("node_count", _cmd_node_count, "显示当前场景中的节点总数")
	register_command("mem", _cmd_mem, "显示内存使用情况")
	register_command("timescale", _cmd_speed, "设置游戏速度 (同 speed)")
	register_command("kill_zombies", _cmd_kill_zombies, "杀死所有僵尸")
	register_command("reload", _cmd_reload, "重新加载当前场景")
	register_command("spawn", _cmd_spawn, "生成僵尸 (spawn <类型名或编号> [行号] [数量])")
	register_command("zombielist", _cmd_zombie_list, "列出所有僵尸类型")


func _cmd_help(_args: Array) -> void:
	print_line("[color=yellow]===== 可用命令 =====[/color]")
	var names := _commands.keys()
	names.sort()
	for cmd_name in names:
		var desc: String = _commands[cmd_name]["description"]
		print_line("  [color=cyan]%s[/color]  -  %s" % [cmd_name, desc])
	print_line("[color=yellow]===================[/color]")


func _cmd_clear(_args: Array) -> void:
	_output_label.clear()


func _cmd_fps(_args: Array) -> void:
	var perf_monitor := get_tree().root.get_node_or_null("PerformanceMonitor")
	# 简单显示当前 FPS
	var fps := Engine.get_frames_per_second()
	print_line("当前 FPS: [color=yellow]%d[/color]" % fps)


func _cmd_speed(args: Array) -> void:
	if args.is_empty():
		print_line("当前游戏速度: [color=yellow]%.2f[/color] 倍" % Engine.time_scale)
		return
	var val: float = args[0].to_float()
	if val <= 0 or val > 20:
		print_line("[color=red]速度必须在 0~20 之间[/color]")
		return
	Engine.time_scale = val
	if Global:
		Global.time_scale = val
	print_line("游戏速度已设为: [color=yellow]%.2f[/color] 倍" % val)


func _cmd_sun(args: Array) -> void:
	if args.is_empty():
		print_line("[color=red]用法: sun <数量>[/color]")
		return
	var val: int = args[0].to_int()
	if val < 0:
		print_line("[color=red]阳光数量不能为负数[/color]")
		return
	EventBus.push_event("test_change_sun_value", [val])
	print_line("阳光已设为: [color=yellow]%d[/color]" % val)


func _cmd_coin(args: Array) -> void:
	if args.is_empty():
		print_line("[color=red]用法: coin <数量>[/color]")
		return
	var val: int = args[0].to_int()
	if val < 0:
		print_line("[color=red]金币数量不能为负数[/color]")
		return
	if Global and Global.global_game_state:
		Global.global_game_state.coin_value = val
		print_line("金币已设为: [color=yellow]%d[/color]" % val)
	else:
		print_line("[color=red]无法设置金币[/color]")


func _cmd_pause(_args: Array) -> void:
	var tree := get_tree()
	tree.paused = not tree.paused
	print_line("游戏%s" % ("[color=yellow]已暂停[/color]" if tree.paused else "[color=lime]已恢复[/color]"))


func _cmd_scene(_args: Array) -> void:
	var current := get_tree().current_scene
	if current:
		print_line("当前场景: [color=cyan]%s[/color]" % current.scene_file_path)
		print_line("场景名称: [color=cyan]%s[/color]" % current.name)
	else:
		print_line("[color=red]无当前场景[/color]")


func _cmd_tree(_args: Array) -> void:
	var current := get_tree().current_scene
	if not current:
		print_line("[color=red]无当前场景[/color]")
		return
	print_line("[color=yellow]场景树概要:[/color]")
	_print_tree_recursive(current, 0, 3)


func _print_tree_recursive(node: Node, depth: int, max_depth: int) -> void:
	if depth > max_depth:
		return
	var indent := "  ".repeat(depth)
	var child_count := node.get_child_count()
	var info := "%s[color=cyan]%s[/color] (%s)" % [indent, node.name, node.get_class()]
	if child_count > 0 and depth == max_depth:
		info += " [%d children]" % child_count
	print_line(info)
	for child in node.get_children():
		_print_tree_recursive(child, depth + 1, max_depth)


func _cmd_eval(args: Array) -> void:
	if args.is_empty():
		print_line("[color=red]用法: eval <表达式>[/color]")
		return
	var expr_text := " ".join(args)
	var expression := Expression.new()
	var error := expression.parse(expr_text, ["Global", "tree"])
	if error != OK:
		print_line("[color=red]表达式解析失败: %s[/color]" % expression.get_error_text())
		return
	var result = expression.execute([Global, get_tree()], self)
	if expression.has_execute_failed():
		print_line("[color=red]表达式执行失败: %s[/color]" % expression.get_error_text())
	else:
		print_line("[color=yellow]=> %s[/color]" % str(result))


func _cmd_quit(_args: Array) -> void:
	print_line("正在退出游戏...")
	get_tree().quit()


func _cmd_fullscreen(_args: Array) -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		print_line("已切换为 [color=yellow]窗口模式[/color]")
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		print_line("已切换为 [color=yellow]全屏模式[/color]")


func _cmd_node_count(_args: Array) -> void:
	var count := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	print_line("当前节点总数: [color=yellow]%d[/color]" % count)


func _cmd_mem(_args: Array) -> void:
	var static_mem := Performance.get_monitor(Performance.MEMORY_STATIC)
	var static_max := Performance.get_monitor(Performance.MEMORY_STATIC_MAX)
	print_line("静态内存: [color=yellow]%.2f MB[/color] / 峰值: [color=yellow]%.2f MB[/color]" % [
		static_mem / 1048576.0, static_max / 1048576.0])


func _cmd_kill_zombies(_args: Array) -> void:
	var zombies := get_tree().get_nodes_in_group("zombie")
	if zombies.is_empty():
		print_line("[color=red]没有找到僵尸 (group: zombie)[/color]")
		return
	var count := zombies.size()
	for z in zombies:
		if z.has_method("die"):
			z.die()
		else:
			z.queue_free()
	print_line("已消灭 [color=yellow]%d[/color] 个僵尸" % count)


func _cmd_reload(_args: Array) -> void:
	print_line("正在重新加载场景...")
	get_tree().reload_current_scene()


## 僵尸名称映射表（简称 -> ZombieType）
const ZOMBIE_ALIAS: Dictionary = {
	"norm": CharacterRegistry.ZombieType.Z001Norm,
	"flag": CharacterRegistry.ZombieType.Z002Flag,
	"cone": CharacterRegistry.ZombieType.Z003Cone,
	"polevaulter": CharacterRegistry.ZombieType.Z004PoleVaulter,
	"bucket": CharacterRegistry.ZombieType.Z005Bucket,
	"paper": CharacterRegistry.ZombieType.Z006Paper,
	"screendoor": CharacterRegistry.ZombieType.Z007ScreenDoor,
	"football": CharacterRegistry.ZombieType.Z008Football,
	"jackson": CharacterRegistry.ZombieType.Z009Jackson,
	"dancer": CharacterRegistry.ZombieType.Z010Dancer,
	"duckytube": CharacterRegistry.ZombieType.Z011Duckytube,
	"snorkle": CharacterRegistry.ZombieType.Z012Snorkle,
	"zamboni": CharacterRegistry.ZombieType.Z013Zamboni,
	"bobsled": CharacterRegistry.ZombieType.Z014Bobsled,
	"dolphin": CharacterRegistry.ZombieType.Z015Dolphinrider,
	"jackbox": CharacterRegistry.ZombieType.Z016Jackbox,
	"balloon": CharacterRegistry.ZombieType.Z017Balloon,
	"digger": CharacterRegistry.ZombieType.Z018Digger,
	"pogo": CharacterRegistry.ZombieType.Z019Pogo,
	"yeti": CharacterRegistry.ZombieType.Z020Yeti,
	"bungi": CharacterRegistry.ZombieType.Z021Bungi,
	"ladder": CharacterRegistry.ZombieType.Z022Ladder,
	"catapult": CharacterRegistry.ZombieType.Z023Catapult,
	"gargantuar": CharacterRegistry.ZombieType.Z024Gargantuar,
	"garg": CharacterRegistry.ZombieType.Z024Gargantuar,
	"imp": CharacterRegistry.ZombieType.Z025Imp,
}


func _resolve_zombie_type(input: String) -> int:
	## 先尝试别名
	var lower := input.to_lower()
	if ZOMBIE_ALIAS.has(lower):
		return ZOMBIE_ALIAS[lower]
	## 尝试直接数字编号
	if input.is_valid_int():
		return input.to_int()
	## 尝试匹配枚举名（如 Z001Norm）
	for key in CharacterRegistry.ZombieType.keys():
		if key.to_lower() == lower:
			return CharacterRegistry.ZombieType[key]
	return -1


func _cmd_spawn(args: Array) -> void:
	if args.is_empty():
		print_line("[color=red]用法: spawn <类型名或编号> [行号0-4] [数量][/color]")
		print_line("[color=red]示例: spawn norm 2    spawn garg 0 3    spawn 1[/color]")
		print_line("[color=red]输入 zombielist 查看所有僵尸类型[/color]")
		return

	if not Global or not Global.main_game:
		print_line("[color=red]当前不在游戏关卡中[/color]")
		return

	var zm: ZombieManager = Global.main_game.zombie_manager
	if not zm:
		print_line("[color=red]找不到 ZombieManager[/color]")
		return

	## 解析僵尸类型
	var type_id := _resolve_zombie_type(args[0])
	if type_id < 0:
		print_line("[color=red]未知僵尸类型: %s[/color]" % args[0])
		return
	var zombie_type: CharacterRegistry.ZombieType = type_id as CharacterRegistry.ZombieType

	## 解析行号（默认随机）
	var max_row: int = zm.all_zombie_rows.size()
	var lane: int = -1
	if args.size() >= 2 and args[1].is_valid_int():
		lane = args[1].to_int()
		if lane < 0 or lane >= max_row:
			print_line("[color=red]行号超出范围 (0-%d)[/color]" % (max_row - 1))
			return

	## 解析数量（默认 1）
	var count: int = 1
	if args.size() >= 3 and args[2].is_valid_int():
		count = clampi(args[2].to_int(), 1, 50)

	var spawned := 0
	for i in count:
		var target_lane := lane
		if target_lane < 0:
			target_lane = randi() % max_row

		var zombie_row = zm.all_zombie_rows[target_lane]
		var spawn_pos: Vector2 = zombie_row.zombie_create_position.global_position + Vector2(randf_range(-10, 10), 0)

		var zombie_init_para: Dictionary = {
			Zombie000Base.E_ZInitAttr.CharacterInitType: Character000Base.E_CharacterInitType.IsNorm,
			Zombie000Base.E_ZInitAttr.Lane: target_lane,
			Zombie000Base.E_ZInitAttr.CurrWave: -1,
		}

		zm.create_norm_zombie(zombie_type, zombie_row, zombie_init_para, spawn_pos)
		spawned += 1

	var type_name: String = CharacterRegistry.ZombieType.keys()[CharacterRegistry.ZombieType.values().find(type_id)]
	print_line("已生成 [color=yellow]%d[/color] 个 [color=cyan]%s[/color]%s" % [
		spawned, type_name,
		" (行 %d)" % lane if lane >= 0 else " (随机行)"
	])


func _cmd_zombie_list(_args: Array) -> void:
	print_line("[color=yellow]===== 僵尸类型列表 =====[/color]")
	for key in CharacterRegistry.ZombieType.keys():
		if key == "Null":
			continue
		var val: int = CharacterRegistry.ZombieType[key]
		## 查找别名
		var aliases: PackedStringArray = []
		for alias_key in ZOMBIE_ALIAS:
			if ZOMBIE_ALIAS[alias_key] == val:
				aliases.append(alias_key)
		var alias_str := " ([color=lime]%s[/color])" % ", ".join(aliases) if not aliases.is_empty() else ""
		print_line("  [color=cyan]%s[/color] = %d%s" % [key, val, alias_str])
	print_line("[color=yellow]=========================[/color]")
