extends SceneTree
## Выгрузка звуков боевых эффектов в WAV для офлайн-проверки (пик/RMS/спектр):
##   Godot --headless --path godot --script res://tests/fx_sounds.gd -- --out=<папка>

func _init() -> void:
	var out := OS.get_user_data_dir()
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var sfx: Node = load("res://scripts/game/sfx.gd").new()
	var names: Array = sfx.FX_SOUNDS.duplicate()
	for k in sfx.SPELL_SOUNDS:
		names.append("spell_" + k)
	names.append_array(["hit", "cast", "stone"])
	for n in names:
		var w: AudioStreamWAV = sfx._stream(n)
		var err := w.save_to_wav(out.path_join(n + ".wav"))
		print(n, " ", err)
	sfx.free()
	quit()
