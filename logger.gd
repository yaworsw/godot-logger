"""
Godot Logger - A comprehensive logging system for Godot 4

This logger provides multiple log levels, colored console output, file logging,
and trace logging capabilities. It's designed to be easy to use while providing
powerful debugging and monitoring features.

LOG LEVELS:
- CRITICAL (0): Critical errors that may cause application failure
- ERROR (1): Errors that prevent normal operation
- WARNING (2): Warnings about potential issues
- INFO (3): General information messages
- DEBUG (4): Detailed debugging information

BASIC USAGE:

1. Create a logger instance:
   var logger = GameLogger.new(GameLogger.INFO, "MyClass", "instance_name")
   
   Parameters:
   - level: Initial log level (default: DEBUG)
   - instance_of: Class/component name (default: "")
   - id: Instance identifier (default: null)

2. Log messages:
   logger.critical("Critical error occurred!")
   logger.error("Something went wrong")
   logger.warning("This might be a problem")
   logger.info("General information")
   logger.debug("Debug details")

3. Enable file logging:
   logger.enable_file_logging([GameLogger.CRITICAL, GameLogger.ERROR, GameLogger.WARNING])
   
   This will write specified log levels to timestamped files in user://logs/

TRACE LOGGING:

Trace logging allows you to log specific events for debugging without cluttering
the console. Traces are only shown when explicitly enabled.

1. Log trace events:
   logger.trace("physics_step", "Starting physics calculation")
   logger.trace("collision_detected", "Player hit enemy")
   
2. Enable specific traces:
   GameLogger.enable_trace("physics_step")
   GameLogger.enable_trace("collision_detected")
   
3. Disable traces:
   GameLogger.disable_trace("physics_step")

EXAMPLE USAGE PATTERNS:

1. Basic class logging:
   var logger: GameLogger
   
   func _ready():
	   logger = GameLogger.new(GameLogger.INFO, "Player", name)
	   logger.info("Player initialized")
   
   func take_damage(amount: int):
	   logger.warning("Player took %d damage" % amount)
	   if health <= 0:
		   logger.critical("Player died!")

2. Physics/logic debugging:
   func _physics_process(delta: float):
	   logger.trace("physics_step", "Starting physics step with delta: %s" % delta)
	   
	   # Your physics code here
	   
	   logger.trace("physics_step", "Physics step completed")

3. File logging for critical events:
   func _ready():
	   logger = GameLogger.new(GameLogger.INFO, "GameManager", "main")
	   logger.enable_file_logging([GameLogger.CRITICAL, GameLogger.ERROR, GameLogger.WARNING])

4. Dynamic level control:
   # Set level for specific logger
   logger.set_level(GameLogger.WARNING)
   
   # Set default level for new loggers
   GameLogger.set_default_level(GameLogger.INFO)

5. Instance management:
   # Change logger instance name
   logger.set_instance_name("NewName")
   
   # Get all registered loggers
   var loggers = GameLogger.get_logger_instances()
   
   # Set level for specific logger by instance key
   GameLogger.set_logger_level("Player#001", GameLogger.DEBUG)

OUTPUT FORMAT:
Console output includes:
- Timestamp: [HH:MM:SS]
- Level: [LEVEL] in colored text
- File info: path/filename:line
- Instance info: (ClassName#id)
- Message

File output is the same but without BBCode formatting.

LOG FILES:
Log files are stored in user://logs/YYYY-MM-DD_HH-MM-SS/ with filenames
matching the logger instance (e.g., "Player#001.log").

TIPS:
- Use trace logging for frequent events like physics steps
- Enable file logging only for important levels to avoid disk space issues
- Use descriptive instance names and IDs for better organization
- Consider disabling debug logging in production builds
- Use trace logging for performance-critical debugging
"""
extends RefCounted
class_name GameLogger

const CRITICAL = 0
const ERROR = 1
const WARNING = 2
const INFO = 3
const DEBUG = 4

const LEVEL_NAMES = {
	CRITICAL: "CRITICAL",
	ERROR: "ERROR",
	WARNING: "WARNING",
	INFO: "INFO",
	DEBUG: "DEBUG"
}

const LEVEL_COLORS = {
	CRITICAL: Color(1, 0, 0),  # Red
	ERROR: Color(1, 0.5, 0),   # Orange
	WARNING: Color(1, 1, 0),   # Yellow
	INFO: Color(0.8, 0.8, 0.8), # Light grey
	DEBUG: Color(0, 1, 1)      # Cyan
}

const TRACE_COLOR = Color(0, 1, 0)  # Bright green

# Static dictionary to track logger instances and their levels
static var _logger_levels: Dictionary = {}
static var _default_level: int = DEBUG
static var _file_loggers: Dictionary = {}  # Track which loggers write to files
static var _file_log_levels: Dictionary = {}  # Track which levels are written to files
static var _log_folder = null  # Current log folder path
static var _enabled_traces: Dictionary = {}  # Track which traces are enabled

static var _id_counter: int = 0

var _instance_of: String = ""
var _id = null
var _instance_file_log_levels: Array = []  # Which levels to write to file for this instance

func _init(level: int = DEBUG, instance_of: String = "", id = null) -> void:
	_instance_of = instance_of
	
	if id == null:
		id = _id_counter
		_id_counter += 1
	_id = id
	
	# Register this logger instance
	var instance_key = _get_instance_key()
	if not _logger_levels.has(instance_key):
		_logger_levels[instance_key] = level
		_file_loggers[instance_key] = false
		_file_log_levels[instance_key] = []

# Enable trace logging for a specific trace name
static func enable_trace(trace_name: String) -> void:
	_enabled_traces[trace_name] = true

# Disable trace logging for a specific trace name
static func disable_trace(trace_name: String) -> void:
	_enabled_traces[trace_name] = false

# Check if a trace is enabled
static func is_trace_enabled(trace_name: String) -> bool:
	return _enabled_traces.get(trace_name, false)

# Get a unique key for this logger instance
func _get_instance_key() -> String:
	var key = _instance_of
	if _id is String:
		key += _id
	elif _id is float or _id is int:
		key += "#%03d" % _id
	return key

# Get the filename for this logger instance
func _get_log_filename() -> String:
	var filename = _instance_of
	if _id != null:
		filename += "-%03d" % _id
	return filename + ".log"

# Ensure log directory exists and return its path
static func _ensure_log_directory() -> String:
	if _log_folder != null:
		return _log_folder

	var datetime = Time.get_datetime_dict_from_system()
	var folder_name = "%04d-%02d-%02d_%02d-%02d-%02d" % [
		datetime.year,
		datetime.month,
		datetime.day,
		datetime.hour,
		datetime.minute,
		datetime.second
	]
	_log_folder = "user://logs/" + folder_name
	
	# Create logs directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir == null:
		push_error("Failed to open user directory")
		return ""
	
	if not dir.dir_exists("logs"):
		var err = dir.make_dir("logs")
		if err != OK:
			push_error("Failed to create logs directory: %d" % err)
			return ""
	
	# Create timestamped directory
	dir = DirAccess.open("user://logs")
	if dir == null:
		push_error("Failed to open logs directory")
		return ""
		
	var err = dir.make_dir(folder_name)
	if err != OK:
		push_error("Failed to create log directory %s: %d" % [folder_name, err])
		return ""
	
	return _log_folder

# Static method to set the default level for new loggers
static func set_default_level(level: int) -> void:
	_default_level = level

# Static method to get all registered logger instances
static func get_logger_instances() -> Array:
	return _logger_levels.keys()

# Static method to set level for a specific logger instance
static func set_logger_level(instance_key: String, level: int) -> void:
	if _logger_levels.has(instance_key):
		_logger_levels[instance_key] = level

# Static method to get level for a specific logger instance
static func get_logger_level(instance_key: String) -> int:
	return _logger_levels.get(instance_key, _default_level)

# Get the current level for this logger instance
func get_level() -> int:
	return get_logger_level(_get_instance_key())

# Set the level for this logger instance
func set_level(level: int) -> void:
	set_logger_level(_get_instance_key(), level)

# Enable file logging for this logger instance
func enable_file_logging(levels_or_traces: Array = []) -> void:
	var instance_key = _get_instance_key()
	_file_loggers[instance_key] = true
	
	# Store the levels or traces for file logging
	_instance_file_log_levels = levels_or_traces if levels_or_traces.size() > 0 else [CRITICAL, ERROR, WARNING, INFO, DEBUG]
	_file_log_levels[instance_key] = _instance_file_log_levels

# Disable file logging for this logger instance
func disable_file_logging(levels: Array = []) -> void:
	var instance_key = _get_instance_key()
	if levels.is_empty():
		# If no levels specified, disable all file logging
		_file_loggers[instance_key] = false
		_instance_file_log_levels = []
	else:
		# Remove specified levels from the instance's log levels
		for level in levels:
			_instance_file_log_levels.erase(level)
		_file_log_levels[instance_key] = _instance_file_log_levels

# Change the instance name for this logger
func set_instance_name(new_name: String) -> void:
	var old_instance_key = _get_instance_key()
	
	# Update the instance name
	_instance_of = new_name
	
	var new_instance_key = _get_instance_key()
	
	# Update the static tracking dictionaries
	if _logger_levels.has(old_instance_key):
		var level = _logger_levels[old_instance_key]
		var file_logging = _file_loggers.get(old_instance_key, false)
		var file_levels = _file_log_levels.get(old_instance_key, [])
		
		# Remove old entry
		_logger_levels.erase(old_instance_key)
		_file_loggers.erase(old_instance_key)
		_file_log_levels.erase(old_instance_key)
		
		# Add new entry
		_logger_levels[new_instance_key] = level
		_file_loggers[new_instance_key] = file_logging
		_file_log_levels[new_instance_key] = file_levels

func _get_timestamp() -> String:
	var datetime = Time.get_datetime_dict_from_system()
	return "[%02d:%02d:%02d]" % [datetime.hour, datetime.minute, datetime.second]

func _get_caller_info() -> Dictionary:
	var stack = get_stack()
	if stack.size() < 3:
		return {"file": "unknown", "line": 0}
	
	# Look for the first caller that's not from the logger itself
	# Start from index 2 (skip current function and immediate caller)
	for i in range(2, stack.size()):
		var frame = stack[i]
		var source = frame.source
		
		# Skip frames that are from the logger itself
		if source.find("logger.gd") != -1:
			continue
		
		return {
			"file": source,
			"line": frame.line
		}
	
	# Fallback to the first non-logger frame or the last frame
	return {
		"file": stack[stack.size() - 1].source,
		"line": stack[stack.size() - 1].line
	}

func _format_message(level_or_trace: Variant, message_or_value: Variant) -> String:
	var timestamp = _get_timestamp()
	var caller = _get_caller_info()
	var file_path = caller.file
	var line = caller.line
	
	# Split file path to get filename
	var file_parts = file_path.split("/")
	var filename = file_parts[file_parts.size() - 1]
	var path = file_path.substr(0, file_path.length() - filename.length())
	
	# Format the log message
	var log_parts = []
	
	# Timestamp (grey)
	log_parts.append("[color=#808080]%s[/color]" % timestamp)
	
	# Level/Trace and file info
	var level_str: String
	if level_or_trace is String:
		# This is a trace message
		level_str = "[color=#%s][TRACE:%s][/color]" % [TRACE_COLOR.to_html(), level_or_trace]
	else:
		# This is a regular log message
		var level_name = LEVEL_NAMES[level_or_trace]
		var level_color = LEVEL_COLORS[level_or_trace]
		level_str = "[color=#%s][%s][/color]" % [level_color.to_html(), level_name]
	
	var file_info = "[color=#808080]%s[/color][b]%s[/b]:[b]%d[/b]" % [path, filename, line]
	log_parts.append("%s %s" % [level_str, file_info])
	
	# Instance info if present
	if _instance_of != "":
		var instance_str = "(%s" % _instance_of
		if _id is String:
			instance_str += _id
		elif _id is float or _id is int:
			instance_str += "#%03d" % _id
		instance_str += ")"
		log_parts.append(instance_str)
	
	# Message/Value
	log_parts.append(str(message_or_value))
	
	return " ".join(log_parts)

func _log(level: int, message: String) -> void:
	if level > get_level():
		return
	
	var formatted_message = _format_message(level, message)
	print_rich(formatted_message)
	
	# Write to file if enabled and level is configured for file logging
	var instance_key = _get_instance_key()
	if _file_loggers.get(instance_key, false) and level in _instance_file_log_levels:
		_write_to_file(formatted_message)

func trace(trace_name: String, value: Variant) -> void:
	# Only print to console if trace is enabled
	if is_trace_enabled(trace_name):
		var formatted_message = _format_message(trace_name, value)
		print_rich(formatted_message)
	
	# Write to file if file logging is enabled for this trace
	var instance_key = _get_instance_key()
	if _file_loggers.get(instance_key, false) and trace_name in _instance_file_log_levels:
		var formatted_message = _format_message(trace_name, value)
		_write_to_file(formatted_message)

func critical(message: String) -> void:
	_log(CRITICAL, message)

func error(message: String) -> void:
	_log(ERROR, message)

func warning(message: String) -> void:
	_log(WARNING, message)

func info(message: String) -> void:
	_log(INFO, message)

func debug(message: String) -> void:
	_log(DEBUG, message)

# Helper function to strip BBCode tags from a string
func _strip_bbcode(text: String) -> String:
	var regex = RegEx.new()
	# Only match BBCode tags that start with [color=, [b], [/b], [/color], etc.
	regex.compile("\\[(?:color=#?[0-9a-fA-F]+|b|/b|/color)\\]")
	return regex.sub(text, "", true)

func _write_to_file(message: String) -> void:
	var log_dir = _ensure_log_directory()
	if log_dir.is_empty():
		push_error("Failed to get log directory path")
		return
		
	var file_path = log_dir.path_join(_get_log_filename())
	
	# Strip BBCode tags before writing to file
	var plain_message = _strip_bbcode(message)
	
	# First check if file exists, if not create it
	if not FileAccess.file_exists(file_path):
		var create_file = FileAccess.open(file_path, FileAccess.WRITE)
		if create_file == null:
			var error = FileAccess.get_open_error()
			push_error("Failed to create log file '%s': Error %d" % [file_path, error])
			return
		create_file.close()
	
	# Open file for reading and writing
	var file = FileAccess.open(file_path, FileAccess.READ_WRITE)
	if file == null:
		var error = FileAccess.get_open_error()
		push_error("Failed to open log file '%s': Error %d" % [file_path, error])
		return
		
	# Try to write to the file
	var write_error = file.get_error()
	if write_error != OK:
		push_error("Failed to write to log file '%s': Error %d" % [file_path, write_error])
		file.close()
		return
		
	file.seek_end()
	file.store_string(plain_message + "\n")
	
	# Check for errors after writing
	write_error = file.get_error()
	if write_error != OK:
		push_error("Failed to write message to log file '%s': Error %d" % [file_path, write_error])
	
	file.close() 
