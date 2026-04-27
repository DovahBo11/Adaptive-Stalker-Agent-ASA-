# Adaptive-Stalker-Agent-ASA-
The Adaptive Stalker Agent (ASA) is a multi-brain AI system built in GDScript for creating intelligent stalker-type enemies.
It is designed to learn player movement habits through rooms/doors, predict likely future movement, and suggest a high-level behavioral action based on those predictions.

ASA is intended to act as a strategic decision layer, not a complete enemy controller.

<h1>Usage</h1>
ASA can be used in two ways:

<h2>1. Global Shared Brain</h2>
Attach the script as a global singleton/autoload.
<ol>
  <li>One shared memory model</li>
  <li>Multiple enemies can reference the same learned movement data</li>
  <li>Lightweight and simple</li>
</ol>
<h2>2. Per-Enemy Instance</h2>
Each enemy has its own ASA instance.
<ol>
  <li>Each enemy has independent intelligence and memory</li>
  <li>Allows different “skill levels” between enemies</li>
  <li>More processing cost (each agent maintains its own model)</li>
</ol>

<h1>Core Systems</h1>
<h2>Variable Order Markov Model (VOMM)</h2>
The ASA uses a Variable Order Markov Model to predict where the player is likely to move next.

Instead of only looking at the most recent room, the VOMM stores patterns of multiple previous rooms (n-grams).
This allows the agent to recognize repeated routes, loops, and common movement paths.
<h3>Input Format</h3>
Transitions are stored as a door token string:<br>
<i>PreviousRoom|CurrentRoom_ModifierA.ModifierB</i><br>
Example:<br>
<i>MainHall|Stairwell_Staircase1.TopFloor</i><br>
You can input transitions manually using:<br>
<i>inputTransition("A|B_mod")</i><br>
Or automatically using inputRoom(), which will buffer two room inputs and generate a transition internally.
<h2>Stored Data Structures</h2>
<h3>History (Room Sequence)</h3>
The VOMM converts door transitions into a clean room history:<br>
<i>_History = ["A", "B", "C", "A", "D"]</i><br>
<h3>Door History</h3>
ASA also stores a frequency dictionary of doors used between room pairs:<br>
<i>_DoorHistory = {
	"A|B": {"A|B_door1": 3, "A|B_door2": 1},
	"B|C": {"B|C_door1": 5}
}</i><br>
This is meant to support future interception/ambush logic.

<h2>VOMM Model</h2>
The core predictive model stores:

prefix → next_token frequency counts
total count per prefix (for probability calculations)

Structure:<br>
<i>VOMM_model[prefix][next_room] = count
prefix_totals[prefix] = total_count</i><br>
Example:<br>
<i>VOMM_model = {
	"A|B": {"C": 4, "D": 1},
	"B|C": {"A": 3}
}</i>

<h3>Prediction</h3>
ASA can predict the next room using weighted probabilities across multiple prefix depths:
<i>predict()</i>
returns:<br>
<i>{
	"C": 0.72,
	"D": 0.28
}</i>

It can also simulate multiple future steps:
<i>predict_n_steps(history, steps)</i>
Example output:<br>
<i>["C", "A", "B", "C"]</i><br>
<h3>Stability / Confidence Scoring</h3>
ASA estimates prediction confidence using an entropy-based stability metric:
<ul>
  <li>dominance (highest probability)</li>
  <li>entropy (randomness of outcomes)</li>
  <li>confidence = 1 - normalized_entropy</li>
  <li>stability = dominance * confidence</li>
</ul>
Higher stability means the movement pattern is more predictable.
<h3>Decay System</h3>
To prevent the model from permanently remembering outdated behavior, ASA includes a decay system.
Every decay_period, stored transition weights are multiplied by decay_rate.
Low-weight transitions are deleted automatically.
This keeps the model adaptive to changing player routes.

<h2>Markov Decision Process (MDP) Action Suggestion</h2>
ASA includes a lightweight MDP-style scoring system which chooses a best action based on the current AI state.

This system does not simulate full reinforcement learning yet.
It is currently a rule-based weighted scoring system that selects the best action using state features.
<h3>MDP State Inputs</h3>
The MDP considers values such as:
<ul>
  <li>player visibility</li>
  <li>distance to player</li>
  <li>prediction stability</li>
  <li>prediction probability spread (entropy)</li>
  <li>last known player location</li>
</ul>
Example state:<br>
<i>{
	"player_visible": false,
	"distance": 12.0,
	"stability": 0.8,
	"prediction": {"C": 0.7, "D": 0.3},
	"last_known_pos": "B",
	"self_room": "A"
}</i><br>
<h3>Available Actions</h3>
ASA defines several possible high-level behaviors:
<ul>
  <li>IDLE</li>
  <li>PATROL</li>
  <li>CHASE</li>
  <li>INTERCEPT</li>
  <li>SEARCH_LAST_KNOWN</li>
  <li>(other actions exist but are currently not implemented in scoring)</li>
</ul>
<h3>Decision Output</h3>
Calling:<br>
<i>MDP_decision(state)</i><br>
Returns the action with the highest score.
A cooldown (decision_cooldown) prevents rapid action flipping.
<h2>Topology (incomplete Feature)</h2>
ASA includes an optional topology system for defining room and door relationships.
Example structure:<br>
<i>_Topology = {
	"RoomA": {"connections": ["Door1"], "tags": ["room"], "ID": null},
	"Door1": {"connections": ["RoomA", "RoomB"], "tags": ["door"], "ID": null}
}</i>
This is currently used mainly to support dead-end checking (_is_dead_end()), and is meant to support smarter navigation logic later.

<h1>Notes / Current Limitations</h1>
The VOMM currently learns room movement patterns, not combat vs stealth contexts.

The MDP system is currently not a true learning MDP (no reinforcement learning or policy training yet).

Many MDP actions are defined but not fully implemented in the scoring logic.

ASA is meant to provide strategic decisions, and should be paired with an FSM, behavior tree, or navigation controller.

<h1>Intended Use</h1>
ASA works best as a “brain module” that feeds decisions into an enemy AI system such as:
<ul>
  <li>Finite State Machine (FSM)</li>
  <li>Behavior Tree</li>
  <li>GOAP-like planners</li>
</ul>
It is not meant to directly move characters, pathfind, or animate enemies.



