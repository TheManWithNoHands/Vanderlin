VERB_MANAGER_SUBSYSTEM_DEF(input)
	name = "Input"
	wait = 1 //SS_TICKER means this runs every tick
	init_order = INIT_ORDER_INPUT
	flags = SS_TICKER
	priority = FIRE_PRIORITY_INPUT
	runlevels = RUNLEVELS_DEFAULT | RUNLEVEL_LOBBY

	use_default_stats = FALSE

	var/list/macro_set

	///running average of how many clicks inputted by a player the server processes every second. used for the subsystem stat entry
	var/clicks_per_second = 0
	///count of how many clicks onto atoms have elapsed before being cleared by fire(). used to average with clicks_per_second.
	var/current_clicks = 0
	///acts like clicks_per_second but only counts the clicks actually processed by SSinput itself while clicks_per_second counts all clicks
	var/delayed_clicks_per_second = 0
	///running average of how many movement iterations from player input the server processes every second. used for the subsystem stat entry
	var/movements_per_second = 0
	///running average of the amount of real time clicks take to truly execute after the command is originally sent to the server.
	///if a click isnt delayed at all then it counts as 0 deciseconds.
	var/average_click_delay = 0

/datum/controller/subsystem/verb_manager/input/Initialize()
	setup_default_macro_sets()

	initialized = TRUE

	refresh_client_macro_sets()

	return ..()

// This is for when macro sets are eventualy datumized
/datum/controller/subsystem/verb_manager/input/proc/setup_default_macro_sets()
	macro_set = list(
	"Any" = "\"KeyDown \[\[*\]\]\"",
	"Any+UP" = "\"KeyUp \[\[*\]\]\"",
	"T" = "say",
	"M" = "me",
	"Back" = "\".winset \\\"input.text=\\\"\\\"\\\"\"",
	"Tab" = "\".winset \\\"input.focus=true?map.focus=true command=disableInput input.text-color = #ad9eb4 input.background-color=[COLOR_INPUT_DISABLED] : input.focus=true command=activeInput input.text-color=#EEEEEE input.background-color=[COLOR_INPUT_ENABLED]\\\"\"",
	"Escape" = "\".winset \\\"input.text=\\\"\\\"\\\"\"")

// Badmins just wanna have fun ♪
/datum/controller/subsystem/verb_manager/input/proc/refresh_client_macro_sets()
	var/list/clients = GLOB.clients
	for(var/i in 1 to clients.len)
		var/client/user = clients[i]
		user.set_macros()
		user.update_movement_keys()

/datum/controller/subsystem/verb_manager/input/fire()
	for(var/mob/user as anything in GLOB.player_list)
		user.focus?.keyLoop(user.client)

/datum/controller/subsystem/verb_manager/input/can_queue_verb(datum/callback/verb_callback/incoming_callback, control)
	//make sure the incoming verb is actually something we specifically want to handle
	if(control != "mapwindow.map")
		return FALSE
	if(average_click_delay >= MAXIMUM_CLICK_LATENCY || !..())
		current_clicks++
		average_click_delay = MC_AVG_FAST_UP_SLOW_DOWN(average_click_delay, 0)
		return FALSE

	return TRUE

///stupid workaround for byond not recognizing the /atom/Click typepath for the queued click callbacks
/atom/proc/_Click(location, control, params)
	if(usr)
		Click(location, control, params)


/datum/controller/subsystem/verb_manager/input/fire()
	var/moves_this_run = 0
	var/deferred_clicks_this_run = 0 //acts like current_clicks but doesnt count clicks that dont get processed by SSinput

	for(var/datum/callback/verb_callback/queued_click as anything in verb_queue)
		if(!istype(queued_click))
			stack_trace("non /datum/callback/verb_callback instance inside SSinput's verb_queue!")
			continue

		average_click_delay = MC_AVG_FAST_UP_SLOW_DOWN(average_click_delay, (REALTIMEOFDAY - queued_click.creation_time) SECONDS)
		queued_click.InvokeAsync()

		current_clicks++
		deferred_clicks_this_run++

	verb_queue.Cut() //is ran all the way through every run, no exceptions

	for(var/mob/user in GLOB.player_list)
		moves_this_run += user.focus?.keyLoop(user.client)//only increments if a player changes their movement input from the last tick

	clicks_per_second = MC_AVG_SECONDS(clicks_per_second, current_clicks, wait TICKS)
	delayed_clicks_per_second = MC_AVG_SECONDS(delayed_clicks_per_second, deferred_clicks_this_run, wait TICKS)
	movements_per_second = MC_AVG_SECONDS(movements_per_second, moves_this_run, wait TICKS)

	current_clicks = 0

/datum/controller/subsystem/verb_manager/input/stat_entry(msg)
	. = ..()
	. += "M/S:[round(movements_per_second,0.01)] | C/S:[round(clicks_per_second,0.01)]([round(delayed_clicks_per_second,0.01)] | CD: [round(average_click_delay,0.01)])"
