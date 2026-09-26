extends Node

# Set mod priority if you want it to load before/after other mods
# Mods are loaded from lowest to highest priority, default is 0
const MOD_PRIORITY = 8
# Name of the mod, used for writing to the logs
const MOD_NAME = "P-TPack"
# Path of the mod folder, automatically generated on runtime
var modPath:String = get_script().resource_path.get_base_dir() + "/"
# Required var for the replaceScene() func to work
var _savedObjects := []


# Initialize the mod
# This function is executed before the majority of the game is loaded
# Only the Tool and Debug AutoLoads are available
# Script and scene replacements should be done here, before the originals are loaded
func _init(modLoader = ModLoader):
	l("Initialized")
	replaceScript("hud/LIDAR.gd","res://hud/LIDAR.gd")
	
	replaceScene("hud/components/LIDAR.tscn")
	replaceScene("enceladus/Upgrades.tscn")
	replaceScene("enceladus/Tuning.tscn")


# Func to print messages to the logs
func l(msg:String, title:String = MOD_NAME):
	Debug.l("[%s]: %s" % [title, msg])

func replaceScript(path:String,old_path:String):
	var childPath:String = str(modPath + path)
	var childScript:Script = load(childPath)
	childScript.new()
	childScript.take_over_path(old_path)

func replaceScene(newPath:String, oldPath:String = ""):
	l("Updating scene: %s" % newPath)
	if oldPath.empty():
		oldPath = str("res://" + newPath)
	newPath = str(modPath + newPath)
	var scene := load(newPath)
	scene.take_over_path(oldPath)
	_savedObjects.append(scene)
	l("Finished updating: %s" % oldPath)
