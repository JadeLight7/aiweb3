extends Node

const DEFAULT_RENDER_PATH := "res://shared/render.png"
const MAX_CAPTURE_ATTEMPTS := 5

@export var capture_on_ready: bool = true


func _ready() -> void:
	if capture_on_ready:
		capture_after_frame(DEFAULT_RENDER_PATH)


func capture_after_frame(output_path: String = DEFAULT_RENDER_PATH) -> void:
	if DisplayServer.get_name() == "headless":
		return

	for attempt in range(MAX_CAPTURE_ATTEMPTS):
		await RenderingServer.frame_post_draw

		var viewport_texture: ViewportTexture = get_viewport().get_texture()
		if viewport_texture == null:
			continue

		var image: Image = viewport_texture.get_image()
		if image == null or image.is_empty():
			continue

		_ensure_output_directory(output_path)

		var error: int = image.save_png(output_path)
		if error != OK:
			push_error("Failed to save screenshot to %s. Error code: %s" % [output_path, error])
		return

	push_error("Failed to capture a valid viewport image for %s." % output_path)


func _ensure_output_directory(output_path: String) -> void:
	var output_dir: String = output_path.get_base_dir()
	if output_dir.is_empty():
		return

	var absolute_dir: String = ProjectSettings.globalize_path(output_dir)
	var error: int = DirAccess.make_dir_recursive_absolute(absolute_dir)
	if error != OK and error != ERR_ALREADY_EXISTS:
		push_error("Failed to create screenshot directory %s. Error code: %s" % [output_dir, error])
