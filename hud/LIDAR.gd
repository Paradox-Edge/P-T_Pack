extends TextureRect

export var scanner = true
onready var dataNode = self

var angle = 0.0
var steps = 360
export var stepsPerSecond = 720
export var jitter = 0.5
export var minDistance = 250.0
export var iffDistanceScale = 0.9
export var sweepDistance = 80000.0
export var distance = 16000.0
export var distanceScale = 0.75
export var pxOffset = 1
export var baseColor = Color(1, 1, 1, 1)
export var clearBackground = false
export var background = Color(0, 0, 0, 1)
export var crossColor = Color(0, 1, 0, 0.5)
export var awareColor = Color(2, 0, 0, 0.5)
export var screenRectColor = Color(0, 0.05, 0.3, 0.2)
export var screenRectColorEnd = Color(0, 0.05, 0.3, 0.0)
export var screenRectShadows = 9
export var screenRectShadowStep = 1.1
export var dopplerScale = 2000.0
export var brightScale = 1.0
export var lineBright = 0.5
export var drawDots = true
export var drawLines = false
export var lineConnectLimit = 0.1
export var lineTrail = 0.1
export var lineWidth = 1.0
export var dopplerMin = 0.2
export var seenExpireSeconds = 10.0
export var centerOffset = Vector2(0, 0)

var exclude = []
var seen = {}

export var rangeFade = 0.0
export var rangeFadeScale = 4.0

export var warnDistance = 1500.0
export var errDistance = 500.0
export var signatureHeatLimit = 1.0
export var signatureScale = 2.0
export var contactGroupLimit = 5

export var warnColor = Color(1, 1, 0.1, 0.02)
export var errColor = Color(1, 0, 0, 0.02)
export var transponderRemovalTime = 60

export var noColor = Color(1, 1, 1, 0)
export var drawCameraRect = true

export var renderingFps = 15.0
onready var renderingTime = 1.0 / renderingFps

export (Color) var rangeMarkerColor = Color(0, 0.05, 0.3, 0.2)
export (PoolRealArray) var rangeMarkers = PoolRealArray([500, 1000, 1500, 2000])
export (float) var rangeMarkerRotation = 30.0
var rangeMarkerNodes = {}

export (PackedScene) var Transponder
export (PackedScene) var RangeMarker = preload("res://hud/components/LidarRangeMarker.tscn")
export (PackedScene) var TacticalMarker = preload("res://hud/components/LidarShipMarker.tscn")
export var showTacticalMarkers = true

export var showRays = false
export var rayColorEdge = Color(0, 1, 0, 1)
export var rayColorCenter = Color(0, 1, 0, 0.5)

export var sweeping = 0
export var timeScaleIndependent = false

var data
var rayData
var astroBlockData
var astroBlockers = {}
var astroBlockersMin = Vector2(0, 0)
var recast = {}
var reader
var field

export var flickerScale = 1
export var flickerTime = 1
var flicker = 0
export var transponderTime = 2.0
export var speedUpTransponders = false

var transponders = {}

onready var busy = Mutex.new()

func draw_circle_arc(center, radius, color, angle_from = 0, angle_to = 360, points = 256, width = 1):
	if radius >= 1 and points >= 2:
		var points_arc = PoolVector2Array()
		points_arc.resize(points + 1)
		for i in range(points + 1):
			
			points_arc[i] = (center + Vector2(radius, 0).rotated(deg2rad(lerp(angle_from, angle_to, float(i) / points))))
			
		draw_polyline(points_arc, color, width, false)

var bpoints = []
var bcolors = []

func multilineDrawAppend(point, color):
	bpoints.append(point)
	bcolors.append(color)
	if bpoints.size() >= Settings.maxVertices:
		multilineDrawExecute()
		
		

func multilineDrawExecute():
	if bpoints.size() > 2:
		draw_multiline_colors(bpoints, bcolors, lineWidth)
	bpoints = []
	bcolors = []
	
func _draw():
	
	if not is_inside_tree():
		return
	if Tool.claim(ship):
		if not ship.isPlayerControlled() and not dynamicConnect:
			Tool.release(ship)
			return
			
		dataNode.busy.lock()
		var sweepVector = Vector2(0, - 1)
		var size = get_rect().size
		var ssize = min(size.x, size.y)
		var center = size / 2 + centerOffset
		var boxSize = Vector2(pxOffset, pxOffset)
		var area = Rect2(Vector2(0, 0), size)
		if clearBackground:
			draw_rect(area, background, true)
		
		var m = distance
		var wd = warnDistance
		if not dynamicConnect:
			wd = reader.getWarnDistance() * 10
			ship.proximityAlert = m / 10
		
		for r in rangeMarkers:
			var d = (10 * r / distance) * ssize * distanceScale
			draw_circle_arc(center, d, rangeMarkerColor)
			if not (r in rangeMarkerNodes):
				var n = RangeMarker.instance()
				n.text = r
				n.modulate = rangeMarkerColor
				rangeMarkerNodes[r] = n
				n.rotation_degrees = rangeMarkerRotation
				
				n.position = center + Vector2(0, d).rotated(deg2rad(rangeMarkerRotation))
				add_child(n)
			else:
				var n = rangeMarkerNodes[r]
				n.position = center + Vector2(0, d).rotated(deg2rad(rangeMarkerRotation))
				
			

		draw_line(Vector2(center.x, 0), Vector2(center.x, size.y), crossColor)
		draw_line(Vector2(0, center.y), Vector2(size.x, center.y), crossColor)
		
		if drawCameraRect:
			var sd = ssize * distanceScale / distance
			for i in range(screenRectShadows):
				var r = dataNode.cameraShipRect
				var s = sd * pow(screenRectShadowStep, i)
				r.position *= s
				r.position += center
				r.size *= s
				var c = lerp(screenRectColor, screenRectColorEnd, float(i) / (screenRectShadows + 1))
				draw_rect(r, c, false)
			
		var cct = 0
		var ccp = Vector2(0, 0)
		var cpr: Rect2
		
		var ld = distance
		for s in range(dataNode.steps):
			var age = posmod(s - dataNode.sweeping, dataNode.steps) / float(dataNode.steps)
			var ageCorrect = pow(age, 0.5)
			var read = dataNode.data[s]
			var sweep = sweepVector.rotated(dataNode.rayData[s].x) * distanceScale
			if showRays:
				multilineDrawAppend(center, rayColorCenter)
				var c = rayColorEdge
				c.a *= ageCorrect
				multilineDrawAppend(center + sweepVector.rotated(dataNode.rayData[s].x) * ssize * 2, c)
			if read:
				if m > read.x:
					m = read.x
				var rd = (read.x / distance)
				var pos = center + sweep * rd * ssize
				var resp = read.z
				var sbs = max(resp - 1, 0) * (1 + sin(flicker * PI * 2 / flickerTime + 2 * PI * s / steps)) * flickerScale / 2
				var bs = boxSize * (clamp(sbs, 0, 1) + 1)
				var r = Rect2(pos - bs / 2, bs)
				var vel = read.y / dopplerScale
				var rf = clamp((read.x / distance - rangeFade) * rangeFadeScale, 0, 1)
				var c = Color(clamp(0.5 - vel, dopplerMin, 1), clamp(0.5 - abs(vel), dopplerMin, 1), clamp(0.5 + vel, dopplerMin, 1), 1) * clamp(resp * rf, 0, 2)
				c.a = ageCorrect
				if drawDots:
					draw_rect(r, c * brightScale, true)

				if drawLines:
					var sweep1 = sweepVector.rotated(dataNode.rayData[s].x - dataNode.rayData[s].y / 2) * distanceScale
					var sweep2 = sweepVector.rotated(dataNode.rayData[s].x + dataNode.rayData[s].y / 2) * distanceScale

					var v = clamp( - vel, - 1, 1)
					
					multilineDrawAppend(center + sweep1 * ssize * rd, c)
					multilineDrawAppend(center + sweep2 * ssize * rd, c)
					multilineDrawAppend(center + sweep1 * ssize * rd, c)
					multilineDrawAppend(center + sweep1 * ssize * (rd + resp * lineTrail), noColor)

					multilineDrawAppend(center + sweep2 * ssize * rd, c)
					multilineDrawAppend(center + sweep2 * ssize * (rd + resp * lineTrail), noColor)
					
					multilineDrawAppend(center + sweep1 * ssize * rd, c)
					multilineDrawAppend(center + sweep * ssize * (rd + v * lineTrail), c)
					multilineDrawAppend(center + sweep2 * ssize * rd, c)
					multilineDrawAppend(center + sweep * ssize * (rd + v * lineTrail), c)

				ld = rd
		multilineDrawExecute()
		dataNode.busy.unlock()
		if m < wd:
			var color = warnColor
			ship.autopilotComfort = false
			if m < errDistance:
				color = errColor
			draw_circle_arc(center, distanceScale * (m / distance) * ssize, color, 0, 360, 256, 2)
		else:
			ship.autopilotComfort = true
		Tool.release(ship)
	
export var dynamicConnect = false

var doppler = false
var speedAdjust = true
var coneSweep = false
var randomSweep = false
var type
func connectToShip():
	ship = reader.getShip()
	if Tool.claim(ship):
		type = ship.getLidarType()
		beams = [{"mask": lidarLightMask, "error": 0, "response": 1}]
		steps = 360
		stepsPerSecond = 720
		jitter = 0.5
		coneSweep = false
		speedAdjust = true
		randomSweep = false
		doppler = true
		drawDots = true
		drawLines = false
		lineTrail = 0.1
		lineWidth = 1.0
		timeScaleIndependent = false
		match type:
			"SYSTEM_LIDAR_RADAR_SPLITBEAM":
				steps = 1440
				doppler = false
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1}, {"mask": lidarLightMask, "error": 0, "response": 1, "offset": 180 * (PI / 180)}]
			"SYSTEM_LIDAR_RADAR_COMB":
				steps = 1440
				stepsPerSecond = 1440
				doppler = false
				jitter = 250
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1, "offset": 10 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1, "offset": 10 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 1, "offset": 350 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1, "offset": 350 * (PI / 180)}]
			"SYSTEM_LIDAR_RADAR_PULSE":
				steps = 720
				stepsPerSecond = 1440
				jitter = 0
				randomSweep = true
				speedAdjust = false
				doppler = false
				drawDots = false
				drawLines = true
				lineTrail = 0.05
				lineWidth = 0.5
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1.0}, {"mask": lidarLightMask, "error": 0, "response": 1.0}, {"mask": lidarRadarMask, "error": 0, "response": 0.8, "offset": 1 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.8, "offset": 1 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.8, "offset": 359 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.8, "offset": 359 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.6, "offset": 2 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.6, "offset": 2 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.6, "offset": 358 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.6, "offset": 358 * (PI / 180)}]
			"SYSTEM_LIDAR_RADIX":
				steps = 720
				stepsPerSecond = 360
				jitter = 0
				doppler = false
				beams = [{"mask": lidarLightMask, "error": 0, "response": 1.0}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 45 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 90 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 135 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 180 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 225 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 270 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 315 * (PI / 180)}]
			"SYSTEM_LIDAR_RADAR_SHELL":
				steps = 540
				stepsPerSecond = 540
				jitter = 0
				doppler = false
				beams = [{"mask": lidarLightMask, "error": 0, "response": 1.0}, {"mask": lidarLightMask, "error": 0, "response": 0.8, "offset": 340 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.8, "offset": 335 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.6, "offset": 315 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.6, "offset": 310 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 0.6, "offset": 305 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 1.0}, {"mask": lidarRadarMask, "error": 0, "response": 0.8, "offset": 340 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.8, "offset": 335 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.6, "offset": 315 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.6, "offset": 310 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 0.6, "offset": 305 * (PI / 180)}]
			"SYSTEM_LIDAR_RADAR_TRIANGLE":
				steps = 1440
				doppler = false
				coneSweep = true
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1.0, "offset": 180 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 180 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 1.0, "offset": 300 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 300 * (PI / 180)}, {"mask": lidarRadarMask, "error": 0, "response": 1.0, "offset": 60 * (PI / 180)}, {"mask": lidarLightMask, "error": 0, "response": 1.0, "offset": 60 * (PI / 180)}]
			"SYSTEM_LIDAR_OPA":
				steps = 1440
				doppler = false
				speedAdjust = false
				randomSweep = true
			"SYSTEM_LIDAR_RADAR":
				doppler = false
				steps = 1440
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1}, {"mask": lidarLightMask, "error": 100.0, "response": 0.2}]
			"SYSTEM_LIDAR_RADAR_CONE":
				coneSweep = true
				steps = 1440
				beams = [{"mask": lidarRadarMask, "error": 0, "response": 1}, {"mask": lidarLightMask, "error": 30.0, "response": 0.2}]
			"SYSTEM_LIDAR_DOPPLER_CONE":
				steps = 720
				coneSweep = true
			"SYSTEM_LIDAR_DOPPLER_HIRES":
				steps = 1440
			"SYSTEM_LIDAR_DOPPLER":
				pass
				
		if (scanner or ship.lidar == null):
			ship.lidar = self
			dataNode = self
			recast.clear()
			if not data or data.size() != steps:
				data = PoolVector3Array()
				rayData = PoolVector3Array()
				astroBlockData = PoolRealArray()
				data.resize(steps)
				rayData.resize(steps)
				astroBlockData.resize(steps)
				
			
			if not ship.is_connected("shipPowerToggle", self, "shipPowered"):
				ship.connect("shipPowerToggle", self, "shipPowered")
		else:
			dataNode = ship.lidar
		field = ship.get_parent()
		onSetup()
		Tool.release(ship)

var ship
func _ready():
	reader = get_parent()
	while not reader.has_method("getSensorReadout"):
		reader = reader.get_parent()
	connectToShip()
	connect("visibility_changed", self, "_visibilityChanged")
	set_physics_process(false)
	set_process(false)
	_visibilityChanged()
	if ship:
		ship.connect("setup", self, "onSetup")
		ship.connect("tuningChanged", self, "onSetup")
		onSetup()
	
func shipPowered(how):
	Debug.l("LIDAR %s power: %s" % [self, how])
	if dynamicConnect:
		set_physics_process(is_visible_in_tree())
	else:
		set_physics_process(how and scanner and ship.isPlayerControlled())


var markerNodes = {}
var transponderNodes = {}
onready var renderingCounter = randf() * renderingTime
func _process(delta):
	var deltaTs = ((delta / Engine.time_scale) if timeScaleIndependent else delta)
	flicker += deltaTs / flickerTime
	renderingCounter += deltaTs
	if renderingCounter > renderingTime:
		renderingCounter -= renderingTime
		render()
	
func render():
	if Tool.claim(ship):
		var size = get_rect().size
		var center = size / 2 + centerOffset
		var ssize = min(size.x, size.y)
						
		var now = CurrentGame.getInGameTimestamp()
		var freeque = []
		var effectiveTransponderTime = transponderTime * (float(steps) / float(stepsPerSecond))
		dataNode.busy.lock()
		for tr in transponderNodes.keys():
			if not tr in dataNode.transponders:
				Tool.remove(transponderNodes[tr])
				transponderNodes.erase(tr)
		
		for tr in dataNode.transponders:
			var trr = dataNode.transponders[tr]
			var age = now - trr.time
			if age > effectiveTransponderTime:
				if tr in transponderNodes:
					if Tool.claim(transponderNodes[tr]):
						transponderNodes[tr].hide(speedUpTransponders)
						Tool.release(transponderNodes[tr])
					
				
			else:
				var rf = clamp((trr.pos.length() / distance - rangeFade) * rangeFadeScale, 0, 1)
				var pos = center - ssize * (trr.pos / distance) * distanceScale
				if not tr in transponderNodes or not Tool.objectValid(transponderNodes[tr]):
					var t = Transponder.instance()
					transponderNodes[tr] = t
					add_child(t)
					t.show(speedUpTransponders)
					
				var tn = transponderNodes[tr]
				tn.text = tr
				tn.position = pos
				tn.show(speedUpTransponders)
				tn.modulate = Color(1, 1, 1, rf)
				
		dataNode.busy.unlock()
		if showTacticalMarkers:
			var rem = markerNodes.keys()
			for h in ship.identifiedShips:
				var n = ship.identifiedShips[h][3]
				var s = ship.identifiedShips[h][2]
				var f = ship.identifiedShips[h][4]
				if (f & 2 != 0) and n and Tool.claim(s):
					var disp = ship.aiGetDispositionTowards(s)
					rem.erase(h)
					var gp = s.global_position - ship.global_position
					var r = s.global_rotation
					
					var away = gp.length() > distance * iffDistanceScale
					if away:
						gp = gp.normalized() * distance * iffDistanceScale
					
					if not h in markerNodes:
						var m = TacticalMarker.instance()
						markerNodes[h] = m
						add_child(m)
						m.appear()
						
					markerNodes[h].setPRA(gp, center, ssize * distanceScale / distance, r, away, disp)
						
					Tool.release(s)
			for h in rem:
				
				markerNodes[h].disappear()
				markerNodes.erase(h)
					
		Tool.release(ship)
		update()
		

func _visibilityChanged():
	if not scanner:
		dataNode = ship.lidar
	var v = is_visible_in_tree()
	set_process(v)
	if dynamicConnect:
		set_physics_process(v)

export (int, LAYERS_2D_PHYSICS) var lidarLightMask = 65535 - 4
export (int, LAYERS_2D_PHYSICS) var lidarRadarMask = 65535 - 5

onready var beams = [{"mask": lidarLightMask, "error": 0, "response": 1}]


onready var soundBleep = get_node_or_null("Bleep")
var cameraShipRect: Rect2 = Rect2(0, 0, 0, 0)

func hasSeen(object):
	return seen.has(hash(object))

func expireSeen():
	var expire = CurrentGame.getInGameTimestamp()
	var x = []
	for i in seen:
		if seen[i] < expire:
			x.append(i)
			
	for i in x:
		seen.erase(i)

func removeOldTransponders():
	var now = CurrentGame.getInGameTimestamp()
	for tr in dataNode.transponders.keys():
		var trr = dataNode.transponders[tr]
		var age = now - trr.time
		
		if age > transponderRemovalTime:
			ship.removeIdentifiedShip(trr.ref, 1)
			dataNode.transponders.erase(tr)

func _physics_process(delta):
	if dynamicConnect:
		connectToShip()
	else:
		if Tool.claim(ship):
			if not ship.isPlayerControlled():
				Tool.release(ship)
				return
			Tool.release(ship)
		else:
			return
			
		if reader.getPower() < 0.8:
			return
	
	if Tool.claim(ship):
		var space_state = ship.get_world_2d().direct_space_state
		if not space_state or not ship.setup or not ship.physicsExcludeInitialSetup:
			Tool.release(ship)
			return

		var redoAstroBlockers = false
		removeOldTransponders()
		if randf() < 0.01:
			expireSeen()
			
		if drawCameraRect:
			var camera = ship.getCamera()
			var viewport: Viewport = camera.get_viewport()
			var viewport_rect: Rect2 = camera.get_viewport_rect()

			var global_to_viewport: Transform2D = viewport.global_canvas_transform * camera.get_canvas_transform()
			var viewport_to_global: Transform2D = global_to_viewport.affine_inverse()

			var viewport_rect_global: Rect2 = viewport_to_global.xform(viewport_rect)
			cameraShipRect = viewport_rect_global
			cameraShipRect.position -= ship.global_position
		
			
		
		var exclude = Tool.multiClaimWhatYouCanAndReturnIt(ship.lidarPhysicsExclude)
		var sweepNow = clamp(delta * stepsPerSecond / max(1, pow(reader.getLag(), 2) * 10), 1, steps)
		busy.lock()
		
		if doppler:
			for psweep in recast:
				var rcd = recast[psweep]
				var ahead = posmod(sweeping - psweep, steps) + 1
				var angle = rayData[psweep].x
				var vec = Vector2(0, - sweepDistance).rotated(angle)
				var psp = ship.global_position
				var phitpoint = space_state.intersect_ray(psp, psp + vec, exclude, rcd.params.mask)
				if phitpoint and exclude:
					var pe = rcd.get("previousError", 0.0)
					var d = (psp - phitpoint.position).length() * reader.getError() + pe
					var l = data[psweep].x
					var vel = ((l - d) / delta)
					data[psweep].y = vel
		
		recast.clear()
		
		var coneAngle = 30.0
		var coneFocus = 1.0
		if coneSweep:
			coneAngle = deg2rad(getConeAngle(ship))
			coneFocus = getConeFocus(ship)
			
		var angleTune = getSweepVelocity(ship)
		var beamsize = float(beams.size())
		var astep = (PI * 2 / float(steps)) * angleTune * beamsize
		
		sweepNow = ceil(sweepNow / beamsize)
		
		for s in range(sweepNow):
			angle = fposmod(angle + astep, PI * 2)
			var rangle = angle + ship.global_rotation + astep * (randf() - 0.5) * jitter
			
			if coneSweep:
				var ca = sin(angle)
				rangle = ship.global_rotation + coneAngle * pow(abs(ca), (coneFocus + 15.0) / 10.0) * sign(ca) / 2.0 + astep * (randf() - 0.5) * jitter
				
			if randomSweep:
				rangle = randf() * PI * 2.0				
				
			
			var mpt = ship.getMaxProximityTowards(Vector2(0, - 1).rotated(rangle))
			for beamParam in beams:			
				var offset = beamParam.get("offset",0.0)
				var nangle = rangle + offset
				sweeping = (sweeping + 1) % steps
				rayData[sweeping] = Vector3(nangle, astep, 0)
				astroBlockData[sweeping] = mpt
				var error = beamParam.error
				var vec = Vector2(0, - sweepDistance).rotated(nangle)
				var hitpoint = space_state.intersect_ray(ship.global_position, ship.global_position + vec, exclude, beamParam.mask)
				if hitpoint and exclude:
					var shash = hash(hitpoint.collider)
					seen[shash] = CurrentGame.getInGameTimestamp() + seenExpireSeconds
					var e = error * randf() * 10.0
					recast[sweeping] = {"params": beamParam, "previousError": e}
					var d = (ship.global_position - hitpoint.position).length() * reader.getError() + e
					data[sweeping].x = d
					var d10 = d / 10
					if mpt > 0 and d10 < mpt:
						astroBlockers[sweeping] = d10
						if not astroBlockersMin.x or d10 < astroBlockersMin.x:
							astroBlockersMin = Vector2(d10, mpt)
							redoAstroBlockers = false
					else:
						if sweeping in astroBlockers:
							astroBlockers.erase(sweeping)
							redoAstroBlockers = true
					var col = hitpoint.collider
					if Tool.claim(col):
						var vel = 0.0
						var resp = 0.8
						if "lidarError" in col:
							var ie = (randf() - 0.5) * col.lidarError * 10.0
							data[sweeping].x += ie
							recast[sweeping].previousError += ie
							e += ie
						if "lidarResponse" in col:
							resp = col.lidarResponse
						resp *= beamParam.response
							
						if col.has_method("getTransponder"):
							var tr = col.getTransponder()
							if tr != "":
								if not (tr in transponders):
									transponders[tr] = {}
									
								transponders[tr].time = CurrentGame.getInGameTimestamp()
								transponders[tr].pos = ship.global_position - col.global_position
								
								var c = col
								var p = col.get_parent()
								while p != field:
									c = p
									p = c.get_parent()
								transponders[tr].ref = c
								ship.addIdentifiedShip(c, tr)

								
						data[sweeping] = Vector3(d, 0, resp)
						if resp > 1 and is_visible_in_tree():
							var w = (1 - clamp(d / distance, 0, 1))
							if soundBleep and doBleep:
								soundBleep.pitch_scale = max(1 + 0.5 * w, 0.1)
								soundBleep.volume_db = w * - 30 - 10
								soundBleep.play()
						Tool.release(col)
				else:
					data[sweeping] = Vector3(0, 0, 0)
					if sweeping in astroBlockers:
						astroBlockers.erase(sweeping)
						redoAstroBlockers = true
		busy.unlock()
		if redoAstroBlockers:
			redoAstroBlockersMin()
		Tool.multiReleaseGlobal()
		Tool.release(ship)

func redoAstroBlockersMin():
	var m = 0.0
	var mx = 0.0
	for s in astroBlockers:
		var v = astroBlockers[s]
		if not m or v < m:
			m = v
			mx = astroBlockData[s]
	astroBlockersMin = Vector2(m, mx)

var doBleep = true
func onSetup():
	if reader.has_method("registerSubsystem"):
		reader.registerSubsystem(
			"TUNE_AUDIO_LIDAR", 
			{
				"type": "bool", 
				"default": true, 
				"current": getBleepSound(ship), 
				"unit": "%", 
				"testProtocol": "lidar", 
				"subsystem": type, 
			})

		if speedAdjust:
			reader.registerSubsystem(
				"TUNE_LIDAR_SPEED", 
				{
					"type": "float", 
					"default": 100.0, 
					"min": 25.0, 
					"max": 400.0, 
					"step": 25.0, 
					"current": getSweepVelocity(ship) * 100, 
					"unit": "%", 
					"testProtocol": "lidar", 
					"subsystem": type, 
				})
		if coneSweep:
			reader.registerSubsystem(
				"TUNE_LIDAR_CONE", 
				{
					"type": "float", 
					"default": 30.0, 
					"min": 5.0, 
					"max": 270.0, 
					"step": 5.0, 
					"current": getConeAngle(ship), 
					"unit": "deg", 
					"testProtocol": "lidar", 
					"subsystem": type, 
				})
			reader.registerSubsystem(
				"TUNE_LIDAR_CONE_FOCUS", 
				{
					"type": "float", 
					"default": 0.0, 
					"min": - 10.0, 
					"max": 10.0, 
					"step": 1.0, 
					"current": getConeFocus(ship), 
					"unit": "", 
					"testProtocol": "lidar", 
					"subsystem": type, 
				})
	doBleep = getBleepSound(ship)

func getSweepVelocity(ship) -> float:
	if ship:
		return ship.getTunedValue("Hud", "TUNE_LIDAR_SPEED", 100.0) / 100.0
	else:
		return 1.0

func getConeAngle(ship) -> float:
	if ship:
		return ship.getTunedValue("Hud", "TUNE_LIDAR_CONE", 30.0)
	else:
		return 30.0
		
func getConeFocus(ship) -> float:
	if ship:
		return ship.getTunedValue("Hud", "TUNE_LIDAR_CONE_FOCUS", 0.0)
	else:
		return 0.0

func getBleepSound(ship) -> bool:
	if ship:
		return ship.getTunedValue("Hud", "TUNE_AUDIO_LIDAR", true)
	else:
		return true
		
