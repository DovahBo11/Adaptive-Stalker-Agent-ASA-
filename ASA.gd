##The "Adaptive Stalker Agent" is a multi-brain AI made for creating intelligant stalker enemies
##[br]this AI can be used 2 ways
##[br]		1: assign as a global script; 
##[br]				simple, one brain for one enemy or multiple enemeies to share
##[br]		2: make an instance for multiple stalker enemies; 
##[br]				varied intellegance across multiple entities, but each takes processing power
class_name ASA
extends Node

""" The "Adaptive Stalker Agent"
this AI can be used 2 ways
		1: assign as a global script; 
				simple, one brain for one enemy or multiple enemeies to share
		2: make an instance for multiple stalker enemies; 
				varied intellegance, but each takes processing power"""

func _process(_delta: float) -> void:
	_VOMM_process()
	_MDP_process(_delta)

"""_______________________________________________________________________________________________________"""
"""help section
to learn how to use the AI"""
#region help
func help():
	print("ASA: Adaptive Stalker Agent\n--------------------")
	print("is a multi-brain AI made for creating intelligant stalker enemies ")
	print("")
func help_HowToUse():
	print("this AI can be used 2 ways\n
		1: assign as a global script; \n
				simple, one brain for one enemy or multiple enemeies to share\n
		2: make an instance for multiple stalker enemies; \n
				varied intellegance, but each takes processing power")
func help_VOMM():
	pass
func help_MDP():
	pass
func help_Topology():
	pass
#endregion

"""_______________________________________________________________________________________________________"""
""" Variable order markov model (VOMM)
for determining player movement through rooms
takes room transitions from "inputTransition", looks through it removing any poisonous/redundant patterns
input sequences should look like 'previous-room|current-room_modifiers'"""
#region VOMM
#region VOMM_AlgorithmVariables
##max_order controls the maximum (n-gram) depth of a pattern that is saved into the [code]VOMM_model[/code] 
##[br]Default: 6 -> "A|B|C|D|E|F":{"G":#}
@export var max_order : int = 6
##the amount patterns decay by for every [member decay_period] 
##[br] float 0.0 - 1.0 
##[br] default: 0.995 
@export var decay_rate : float = 0.995
##the time in frames for every decay instance 
##[br] [code]decay period = (frame<=60)*(sec<=60)*(min<=60)*(hr<24)[/code]
##[br]default: 60*30*1*1 = 30 seconds
@export var decay_period : float = 60*30*1*1 # (frame<=60)*(sec<=60)*(min<=60)*(hr<24)
##the active internal timer for decaying
##to reset timer: [code]decay_timer=decay_period[/code]
var decay_timer := decay_period
@export var min_stability_threshold : float = 0.6 # minimum amount needed for confidence of interception
@export var min_observations : int = 2 # minimum before is begins taking the pattern into account
#endregion

## placed in _process, to run frame by frame operations
func _VOMM_process():
	if _is_inserting || _is_decaying:
		return
	if decay_timer <= 0:
		_decay_all()
		print("decayed") # TESTING
		decay_timer=decay_period
	decay_timer=decay_timer-1
	
	if roomInputTimerOn==true:# checks to see if the timer for the room input is active
		if roomInputTimer<=0:
			inputRoom()
		else: roomInputTimer-=1
	

##variable to delay behavior & reduce corruption
var _is_decaying : bool
##variable to delay behavior & reduce corruption
var _is_inserting : bool

var roomInputTimerOn:bool
var roomInputTimer:int=0
var roomInputPeriod:int=30
##used to input rooms into a list
##[br]once two are inside the list it will combine them into a valid room transition
##[br]best used if it is difficult to use inputTransition() within your framework
var _inputRoom:=[]
func inputRoom(room: String="") -> void:
	if room=="":
		_inputRoom.clear()
		roomInputTimerOn=false
		return
	# Don't add the same room twice in a row
	if _inputRoom.size() == 1 and _inputRoom[0] == room:
		return
	_inputRoom.append(room)
	if _inputRoom.size() == 2:
		# Extract parts: [RoomName, Mod] or [RoomName, ""]
		var p1 = _inputRoom[0].split("_") if "_" in _inputRoom[0] else [_inputRoom[0], ""]
		var p2 = _inputRoom[1].split("_") if "_" in _inputRoom[1] else [_inputRoom[1], ""]
		
		# Build the transition string: "RoomA|RoomB_ModA.ModB"
		var transition = "%s|%s_%s.%s" % [p1[0], p2[0], p1[1], p2[1]]
		
		inputTransition(transition)
		_inputRoom.clear() # Reset for the next transition
		roomInputTimerOn=false
		roomInputTimer=-1
		return
	roomInputTimerOn=true
	roomInputTimer=roomInputPeriod

## array used for inputting, verifying, and then inserting transitions
##[br]DO NOT USE DIRECTLY use: [member inputTransition]
var _input := []
##used to input the room transitions into [member _input]
##[br] input transitions like "<prevRoom name>|<currentRoom name>_<additional modifiers to increase uniqueness>"
##[br] it is suggested to input "roomname->roomname_modifiers" but is can still handle "|" instead of "->" or "<-"
func inputTransition(TransitionName: String):
	TransitionName=refactorTransition(TransitionName)
	_input.append(TransitionName)
	_input=_clean_with_rewind(_input)
	if (_input_rolledBack==false || _insert_delay<=0) && _input.size()>2: 
		_insert_DoorHistory(_input[-3])
		if _input.size() >= max(max_order, 5):
			_insert_Input(_input.slice(0, _input.size()-max_order))
	if _input.size()>=10:
		_input=_input.slice(_input.size()-10, _input.size())
func refactorTransition(TransitionName:String)->String:
	var NewTransitionName: String
	if not (TransitionName.contains("->") || TransitionName.contains("<-")) && TransitionName.contains("|"):
		return TransitionName 
	if TransitionName.contains("->"):
		NewTransitionName=TransitionName.replace("->","|")
	if TransitionName.contains("<-"): # "currentRoom<-prevRoom_mod" -> "prevRoom|currentRoom_mod"
		TransitionName=TransitionName.replace("<-","|")
		var split_pipe = TransitionName.split("|")
		var currentRoom = split_pipe[0]
		var split_underscore = split_pipe[1].split("_", true, 1)
		var prevRoom = split_underscore[0]
		var modifiers = "_" + split_underscore[1] if split_underscore.size() > 1 else ""

		# 3. Reassemble in the new order
		NewTransitionName = "%s|%s%s" % [prevRoom, currentRoom, modifiers]
	return NewTransitionName

##delays the insert when [member _input] is [member _clean_with_rewind]
var _insert_delay := 0
##bool variable to check if [member _input] was rolled back during [member _clean_with_rewind]
var _input_rolledBack : bool # checks if it was rolled back so that it doesn't insert arbitrary patterns
##cuts out poisonous patterns and then rewinds the input ▼
##[br]['?','?|A_#','A|B_#','A|B_#'] --(cut)--> ['?','?|A_#']
##[br]the only exceptions are for rooms with dead ends
func _clean_with_rewind(input:Array) -> Array:
	var path:=input.duplicate(true) #deep copy the input list into it
	var changed: bool=false
	if path.size()>=2 && path[-1]==path[-2]: # cuts out [?|A_#,A|B_#,A|B_#]->[?|A_#]
		#WIP: needs to check if either room is a dead end within the last input
		path=path.slice(0,path.size()-2)
		_input_rolledBack=true
		_insert_delay=3
		changed=true
		return path
	if changed==false:
		_insert_delay-=1
	return path

func _door_to_pair(door_token:String) -> String:
	var underscore = door_token.find("_")
	if underscore == -1:
		return door_token
	return door_token.substr(0, underscore)

func _door_to_rooms(door_token:String) -> Array:
	var pair = _door_to_pair(door_token) # "A|B"
	return pair.split("|") # ["A","B"]

func _door_sequence_to_room_sequence(door_sequence:Array) -> Array:
	var rooms := []

	for i in range(door_sequence.size()):
		var r = _door_to_rooms(door_sequence[i]) # ["A","B"]
		if r.size() != 2:
			continue
		if rooms.is_empty():
			rooms.append(r[0])
			rooms.append(r[1])
		else:
			# only append the new room
			if rooms[-1] == r[0]:
				rooms.append(r[1])
			elif rooms[-1] == r[1]:
				rooms.append(r[0])
			else:
				# discontinuity (bad data / teleport / cleaning issue)
				# force reset by appending both
				rooms.append(r[0])
				rooms.append(r[1])
	return rooms

##used for inserting veryfied and cleaned sequences into the [member VOMM_model] with [member _insert]
##[br]["A","B","C"]
var _History := []
# inserts the good cleaned sequences
##inserts the cleaned sequences into [member _History]
func _insert_Input(sequence:Array) -> void:
	var room_path = _door_sequence_to_room_sequence(sequence)
	if room_path.size() < 2:
		return

	_History = room_path.duplicate(true)
	_insert(_History)

##stores door history to support ambush/interception faculties
##[br]the structure ▼
##[br]{
##[br]	'A|B':{"A-B_1":#, "A-B_2":#},
##[br]	'B|R':{"R-B_1":#}
##[br]	'MainHall|2ndMainHall':{"MainHall-2ndMainHall_Staircase1":#, "MainHall-2ndMainHall_Staircase2":#}
##[br]	'2ndMainHall|MainHall':{"MainHall-2ndMainHall_Staircase1":#, "MainHall-2ndMainHall_Staircase2":#}
##[br]}
var _DoorHistory := {}
## inserts the [code]prevRoom[/code] & [code]door[/code] & [code]currentRoom[/code] into [member _DoorHistory]
##[br] "prevRoom|currentRoom":{"door"=#}
func _insert_DoorHistory(door_token:String) -> void:
	var pair = _door_to_pair(door_token) # "A|B"

	if not _DoorHistory.has(pair):
		_DoorHistory[pair] = {}

	_DoorHistory[pair][door_token] = _DoorHistory[pair].get(door_token, 0) + 1

## the array contains the patterns and the number of times they have been used
##[br] VOMM_model[prefix][next_token] = float_count
## EX:  VOMM_model['E|D|C|B']['A'] = float_count
##[br] the structure ▼
##[br]{
##[br]	"A":{"A-Z":#},
##[br]	"B|A":{},
##[br]	"C|B|A":{},
##[br]	"D|C|B|A":{},
##[br]	"E|D|C|B|A":{}
##[br]	"G":{""},
##[br]	"R|G":{},
##[br]	"P|R|G":{},
##[br]	...
##[br]}
var VOMM_model := {}

##works in tandem with the [member VOMM_model], tracks total transitions per prefix
var prefix_totals := {}

## turns the list of rooms into a prefix key
##[br]used for both making new saved patterns and searching for saved patterns
##[br] [code]VOMM_model[prefix]={"future"=#}[/code]
func _make_key(prefix: Array) -> String:
	return "|".join(prefix)

## inserting data into the [member VOMM_model]
#		need to figure out how to ensure that movement data during combat data doesn't get recorded
func _insert(sequence: Array, weight: float = 1.0) -> void:
	_is_inserting = true

	if sequence.size() < 2:
		_is_inserting = false
		return

	for order in range(1, min(max_order, sequence.size())):
		var arr_prefix = sequence.slice(sequence.size() - order - 1, sequence.size() - 1)
		var next_token = sequence[-1]
		var prefix = _make_key(arr_prefix)

		if not VOMM_model.has(prefix):
			VOMM_model[prefix] = {}
			prefix_totals[prefix] = 0.0

		VOMM_model[prefix][next_token] = VOMM_model[prefix].get(next_token, 0.0) + weight
		prefix_totals[prefix] += weight

	_is_inserting = false

## gets the probability of that room being next
func _compute_probabilities(prefix: String) -> Dictionary:
	# gets the count of each prefix's token and then divides equaliy by the total tokens in the dict
	var result := {}
	
	var total = prefix_totals[prefix]
	
	if total <= 0:
		return result
	for token in VOMM_model[prefix]:
		result[token] = VOMM_model[prefix][token] / total
	
	return result

## predicts the very next room based on the context
func predict(history: Array = _History) -> Dictionary:
	var prediction:={}
	var weight_total:=0.0
	
	# max_depth = whichever is smaller, the history size or the max order
	var max_depth = min(max_order, history.size())
	
	# goes through the history to find matching patterns throughout the whole depth
	for order in range(1, max_depth+1):
		var arr_prefix = history.slice(history.size() - order, history.size())
		var prefix = _make_key(arr_prefix)
		
		if VOMM_model.has(prefix):
			var probs = _compute_probabilities(prefix)
			
			# higher orders have heavier weight
			var weight=_get_stability(prefix) * (order/float(max_depth))
			weight *= clamp(prefix_totals[prefix]/min_observations, 0, 1)
			
			for token in probs: 
				prediction[token] = prediction.get(token, 0.0) + probs[token] * weight
			
			weight_total+=weight
	
	if weight_total > 0:
		for token in prediction:
			prediction[token]/=weight_total
	return prediction

## predicts the most likely future movements the player will make up to [code]steps[/code]
func predict_n_steps(history: Array = _History, steps: int = 6) -> Array:
	
	var simulated_history = history.duplicate(true)
	var result := []
	
	for i in range(steps):
		var probs = predict(simulated_history)
		
		if probs.is_empty():
			break
		
		var next_token = _get_highest_probability(probs)
		
		result.append(next_token)
		simulated_history.append(next_token)
		
		if simulated_history.size() > max_order:
			simulated_history.pop_front()
	
	return result

## takes in an array of (key:probability) and selects the best one
#		needs work to make it so it doesn't choose the FIRST highest probability
func _get_highest_probability(prob_dict: Dictionary) -> String:
	var best_token := ""
	var best_value := -1.0
	
	for token in prob_dict:
		if prob_dict[token] > best_value:
			best_value = prob_dict[token]
			best_token = token
	
	return best_token

## how confident is the model that the next move is actually predictable, 
## uses [member _History] 
## calculations ▼
##[br]dominance = max_probability
##[br]entropy = -Σ(p * log(p))
##[br]normalized_entropy = entropy / log(n)
##[br]confidence = 1 - normalized_entropy
##[br]stability = dominance * confidence
func _get_stability(prefix: String) -> float:
	""" calculations ▼
	dominance = max_probability
	entropy = -Σ(p * log(p))
	normalized_entropy = entropy / log(n)
	confidence = 1 - normalized_entropy
	stability = dominance * confidence
	"""
	
	if not VOMM_model.has(prefix):
		return 0.0

	var outcomes = VOMM_model[prefix]
	var totalOutcomes:=0.0
	for token in outcomes:
		totalOutcomes += outcomes[token]
	if totalOutcomes==0.0: return 0.0

	var dominance := 0.0
	var entropy := 0.0
	var n = outcomes.size()

	for token in outcomes:
		var p = outcomes[token] / totalOutcomes
		dominance = max(dominance, p)
		if p > 0:
			entropy -= p * log(p)

	if n <= 1:
		return dominance

	var max_entropy = log(n)
	var normalized_entropy = entropy / max_entropy
	var confidence = 1.0 - normalized_entropy

	return dominance * confidence

##method to handle decaying all of the hashmap values
##[br]decays patterns that arent used
func _decay_all():
	_is_decaying = true

	var prefixes = VOMM_model.keys()
	for prefix in prefixes:
		var tokens = VOMM_model[prefix].keys()
		var new_total := 0.0
		for token in tokens:
			VOMM_model[prefix][token] *= decay_rate
			if VOMM_model[prefix][token] < 0.01:
				VOMM_model[prefix].erase(token)
			else:
				new_total += VOMM_model[prefix][token]
		prefix_totals[prefix] = new_total
		if VOMM_model[prefix].is_empty():
			VOMM_model.erase(prefix)
			prefix_totals.erase(prefix)

	_is_decaying = false

#endregion

"""_______________________________________________________________________________________________________"""
"""Markov Decision Process (MDP)
"""
#region MDP

# the weights for everything that is considered
@export var w_visibility := 3.0
@export var w_distance := -0.05
@export var w_stability := 2.5
@export var w_recent_seen := 2.0
@export var w_uncertainty := -2.0
@export var w_door_confidence := 2.0
@export var w_patrol_bias := 0.3

##what is considered by the MDP when calulating best policy
var MDP_State := {
	"player_visible":false,
	"distance":0.0,
	"stability":0.0,
	"prediction":{},
	"last_known_pos":"",
	"self_room":""
}

##what the MDP can assign as best policy
enum MDP_Action{
	IDLE,# waits with no specific purpose
	IDLE_HIGH_TRAFFIC,# goes to the room with highest traffic and waits
	PATROL,# wanders through the map
	CHASE,# normal chase
	INTERCEPT,# goes to target room and sees if player is there
	INTERCEPT_AMBUSH,# goes to target room and waits for player to enter the room
	INTERCEPT_BACKTRACK,# moves down the predicted path meet up with the target
	SEARCH,# normal search, searches inside the current room and connected rooms according to the topology
	SEARCH_LAST_KNOWN,# goes to where player last seen
	SEARCH_HIGH_TRAFFIC,# searches the areas on the map with high traffic
	INVESTIGATE# more specific search
}

# Soft lock to prevent rapid action switching
@export var decision_cooldown := 1.0

var _last_action := MDP_Action.IDLE
var _decision_timer := 0.0

func _MDP_process(delta:float)->void:
	if _decision_timer > 0.0:
		_decision_timer-=delta

##returns the optimal action based on the current state
func MDP_decision(state: Dictionary)->MDP_Action:
	# cooldown prevents flip-flopping every frame
	if _decision_timer > 0.0:
		return _last_action

	var scores := {}
	for action in MDP_Action.values():
		scores[action] = _score_action(state, action)

	var best_action = _BestAction(scores)

	_last_action = best_action
	_decision_timer = decision_cooldown
	return best_action

func _score_action(state: Dictionary, action: MDP_Action)->float:
	var visible = state.get("player_visible", false)
	var distance = state.get("distance", 9999.0)
	var stability = state.get("stability", 0.0)
	var prediction = state.get("prediction", {})
	var last_known_pos = state.get("last_known_pos", "")

	var score := 0.0

	match action:
		MDP_Action.IDLE:
			if not visible and last_known_pos == "":
				score += 2.0
			score -= stability * 0.5
		MDP_Action.CHASE:
			if visible:
				score += w_visibility
			score += w_distance * distance
		MDP_Action.INTERCEPT:
			if visible:
				score -= 5.0
			if prediction.is_empty():
				score -= 999.0
			else:
				score += w_stability * stability
				score += _BestValue(prediction) * 2.0
				score += w_uncertainty * _entropy(prediction)
		MDP_Action.SEARCH_LAST_KNOWN:
			if visible:
				score -= 5.0
			if last_known_pos != "":
				score += 3.0
			score += w_distance * distance
		MDP_Action.PATROL:
			if visible:
				score -= 3.0
			score += w_patrol_bias
			score -= stability * 0.8
		_:
			score = -1.0 # fallback so unimplemented actions aren't chosen

	return score

func _BestAction(scores:Dictionary)->MDP_Action:
	var best_action := MDP_Action.IDLE
	var best_val := -INF

	for k in scores.keys():
		var v = scores[k]
		if v > best_val:
			best_val = v
			best_action = k

	return best_action

func _BestValue(d: Dictionary)->float:
	var best := 0.0
	for k in d:
		best = max(best, float(d[k]))
	return best

func _entropy(prob_dict: Dictionary)->float:
	# assumes values already sum to ~1
	# entropy in range [0, log(n)]
	var entropy := 0.0
	for k in prob_dict:
		var p := float(prob_dict[k])
		if p > 0.0:
			entropy -= p * log(p)
	return entropy

#endregion

"""_______________________________________________________________________________________________________"""
"""Topology
an additive feature to allow the Agent the ability to understand it's environment"""
#region Topology
##the AI's knowledge of its surroundings, it can work without a defined topology however it uses it to have knowledge of unique room/door information
##[br][code]"example_room":{"connections": ["door"], "tags": ["room"], "ID": Node}
##"exemple_door":{"connections": ["room"], "tags": ["room"], "ID": Node}[/code]
##[br]Supported Tags for rooms: "room", "", "dead_end", "", "", ""
##[br]Supported Tags for doors: "door", "locked", "broken"
var _Topology := {
	"example_room":{"connections":["exemple_door"], "tags":["room"], "ID":null},
	"exemple_door":{"connections":["example_room"], "tags":["door"], "ID":null}
}
##used to register a room or door into the topology
func register_topology(Name:String, connections:Array=[], tags:Array=[]):
	if Name.is_empty():
		push_error("attempting to insert an entry with no name")
		return
	if _Topology.has(Name):
		return
	_Topology[Name] = {
		"connections": connections.duplicate(true),
		"tags": tags.duplicate(true)
	}
	return
##used to delete a registered room or door from the topology
func delete_topology(Name:String):
	if Name.is_empty():
		push_error("attempting to delete an entry with no name")
		return
	if _Topology.rooms.contains(Name): 
		_Topology.rooms[Name].erase()
		return
	if _Topology.doors.contains(Name):
		_Topology.doors[Name].erase()
		return
	push_error("attempting to erase a entry that does not exist")
##changes the connections and or the tags of a target room
##[br]CURRENTLY NOT IMPLEMENTED
func change_topology(Name:String, connections:Array=[], tags:Array=[]):
	if Name.is_empty():
		push_error("attempting to alter a entry with no name")
		return
	if connections.is_empty():
		pass
	if tags.is_empty():
		pass
##used to check if that room token is a dead end so the inputted pattern isn't arbitrarily deleted in [member _clean_with_rewind]
func _is_dead_end(room:String) -> bool:
	if not _Topology.has(room):
		return false
	if "dead_end" in _Topology[room]["tags"]:
		return true
	if _Topology[room]["connections"].size() <= 1:
		return true
	return false
#endregion
