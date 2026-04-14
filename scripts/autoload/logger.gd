extends Node
## 日志管理器 autoload
## 将游戏运行日志保存到文件，方便查看崩溃日志
## 日志位置：user://logs/game_log_<时间戳>.txt
## Windows 路径：%APPDATA%/Godot/app_userdata/<项目名>/logs/

const MAX_LOG_FILES := 10
const LOG_DIR := "user://logs/"

var _log_file: FileAccess
var _log_path: String

func _ready() -> void:
	_ensure_log_dir()
	_cleanup_old_logs()
	_open_log_file()
	_log_system_info()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		info("游戏正常关闭")
		_close_log_file()

## 确保日志目录存在
func _ensure_log_dir() -> void:
	if not DirAccess.dir_exists_absolute(LOG_DIR):
		DirAccess.make_dir_recursive_absolute(LOG_DIR)

## 清理旧日志文件，只保留最近 MAX_LOG_FILES 个
func _cleanup_old_logs() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.begins_with("game_log_") and file_name.ends_with(".txt"):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	files.sort()
	while files.size() >= MAX_LOG_FILES:
		var old_file: String = files.pop_front()
		dir.remove(old_file)

## 打开新的日志文件
func _open_log_file() -> void:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	_log_path = LOG_DIR + "game_log_%s.txt" % timestamp
	_log_file = FileAccess.open(_log_path, FileAccess.WRITE)
	if _log_file == null:
		push_error("Logger: 无法创建日志文件: %s" % _log_path)

## 关闭日志文件
func _close_log_file() -> void:
	if _log_file != null:
		_log_file.flush()
		_log_file = null

## 记录系统信息
func _log_system_info() -> void:
	_write_line("========== 游戏启动 ==========")
	_write_line("时间: %s" % Time.get_datetime_string_from_system())
	_write_line("引擎版本: %s" % Engine.get_version_info().string)
	_write_line("OS: %s" % OS.get_name())
	_write_line("渲染器: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	_write_line("显卡: %s" % RenderingServer.get_video_adapter_name())
	_write_line("分辨率: %s" % str(DisplayServer.window_get_size()))
	_write_line("===============================")

## 写入一行日志
func _write_line(text: String) -> void:
	if _log_file != null:
		_log_file.store_line(text)
		_log_file.flush()

## 获取当前时间字符串
func _timestamp() -> String:
	var time := Time.get_time_dict_from_system()
	var msec := Time.get_ticks_msec() % 1000
	return "%02d:%02d:%02d.%03d" % [time.hour, time.minute, time.second, msec]

#region 公开日志方法
## 普通信息日志
func info(msg: String) -> void:
	var line := "[%s] [INFO] %s" % [_timestamp(), msg]
	_write_line(line)
	print(line)

## 警告日志
func warn(msg: String) -> void:
	var line := "[%s] [WARN] %s" % [_timestamp(), msg]
	_write_line(line)
	push_warning(line)

## 错误日志
func error(msg: String) -> void:
	var line := "[%s] [ERROR] %s" % [_timestamp(), msg]
	_write_line(line)
	push_error(line)

## 网络相关日志
func log_net(msg: String) -> void:
	var line := "[%s] [NET] %s" % [_timestamp(), msg]
	_write_line(line)
	print(line)
#endregion

## 获取日志文件的完整路径（方便用户查找）
func get_log_path() -> String:
	return ProjectSettings.globalize_path(_log_path)
