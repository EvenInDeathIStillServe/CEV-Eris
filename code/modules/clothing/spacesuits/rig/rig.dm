#define ONLY_DEPLOY 1
#define ONLY_RETRACT 2
#define SEAL_DELAY 25


#define RIG_SECURITY 1
#define RIG_AI_OVERRIDE 2
#define RIG_SYSTEM_CONTROL 4
#define RIG_INTERFACE_LOCK 8
#define RIG_INTERFACE_SHOCK 16
/*
 * Defines the behavior of hardsuits/rigs/power armour.
 */

/obj/item/weapon/rig

	name = "hardsuit control module"
	icon = 'icons/obj/rig_modules.dmi'
	desc = "A back-mounted hardsuit deployment and control mechanism."
	slot_flags = SLOT_BACK
	req_one_access = list()
	req_access = list()
	w_class = ITEM_SIZE_LARGE
	item_flags = DRAG_AND_DROP_UNEQUIP|EQUIP_SOUNDS

	// These values are passed on to all component pieces.
	armor = list(melee = 40, bullet = 35, laser = 35,energy = 35, bomb = 35, bio = 100, rad = 40)
	min_cold_protection_temperature = SPACE_SUIT_MIN_COLD_PROTECTION_TEMPERATURE
	max_heat_protection_temperature = SPACE_SUIT_MAX_HEAT_PROTECTION_TEMPERATURE
	siemens_coefficient = 0.2
	permeability_coefficient = 0.1
	unacidable = 1

	var/interface_path = "hardsuit.tmpl"
	var/ai_interface_path = "hardsuit.tmpl"
	var/interface_title = "Hardsuit Controller"
	var/datum/delay_controller/wearer_move_delayer = new
	var/ai_controlled_move_delay = 10

	// Keeps track of what this rig should spawn with.
	var/suit_type = "hardsuit"
	var/list/initial_modules = list()
	var/chest_type = /obj/item/clothing/suit/space/rig
	var/helm_type =  /obj/item/clothing/head/helmet/space/rig
	var/boot_type =  /obj/item/clothing/shoes/magboots/rig
	var/glove_type = /obj/item/clothing/gloves/rig
	var/cell_type =  /obj/item/weapon/cell/large/high
	var/air_type =   /obj/item/weapon/tank/oxygen

	//Component/device holders.
	var/obj/item/weapon/tank/air_supply                       // Air tank, if any.
	var/obj/item/clothing/shoes/boots = null                  // Deployable boots, if any.
	var/obj/item/clothing/suit/space/rig/chest                // Deployable chestpiece, if any.
	var/obj/item/clothing/head/helmet/space/rig/helmet = null // Deployable helmet, if any.
	var/obj/item/clothing/gloves/rig/gloves = null            // Deployable gauntlets, if any.
	var/obj/item/weapon/cell/large/cell                             // Power supply, if any.
	var/obj/item/rig_module/selected_module = null            // Primary system (used with middle-click)
	var/obj/item/rig_module/vision/visor                      // Kinda shitty to have a var for a module, but saves time.
	var/obj/item/rig_module/voice/speech                      // As above.
	var/obj/item/rig_module/storage/storage					  // var for installed storage module, if any
	var/mob/living/carbon/human/wearer                        // The person currently wearing the rig.
	var/image/mob_icon                                        // Holder for on-mob icon.
	var/list/installed_modules = list()                       // Power consumption/use bookkeeping.

	// Rig status vars.
	var/active = FALSE
	var/open = 0                                              // Access panel status.
	var/locked = 1 // Lock status. 0 = unlocked, 1 = locked with ID, -1 = broken lock, permanantly unlocked
	var/subverted = 0
	var/interface_locked = 0
	var/control_overridden = 0
	var/ai_override_enabled = 0
	var/security_check_enabled = 1
	var/malfunctioning = 0
	var/malfunction_delay = 0
	var/electrified = 0
	var/locked_down = 0

	var/seal_delay = SEAL_DELAY
	var/sealing                                               // Keeps track of seal status independantly of canremove.
	var/offline = 1                                           // Should we be applying suit maluses?
	var/offline_slowdown = 3                                  // If the suit is deployed and unpowered, it sets slowdown to this.
	var/vision_restriction
	var/offline_vision_restriction = 1                        // 0 - none, 1 - welder vision, 2 - blind. Maybe move this to helmets.
	var/airtight = 1 //If set, will adjust AIRTIGHT and STOPPRESSUREDAMAGE flags on components. Otherwise it should leave them untouched.

	var/emp_protection = 0

	var/rig_wear_slot = slot_back //Changing this allows for rigs that are worn as a belt or a tie or something

	// Wiring! How exciting.
	var/datum/wires/rig/wires
	var/datum/effect/system/spark_spread/spark_system


	//Stuff rigs can store
	allowed = list(
	/obj/item/weapon/storage/pouch/,
	/obj/item/weapon/gun,
	/obj/item/weapon/melee/baton,
	/obj/item/weapon/melee/energy/sword,
	/obj/item/ammo_magazine,
	/obj/item/ammo_casing,
	/obj/item/weapon/melee/baton,
	/obj/item/weapon/handcuffs,
	/obj/item/weapon/tank,
	/obj/item/device/suit_cooling_unit,
	/obj/item/weapon/cell,
	/obj/item/weapon/handcuffs)

	var/list/extra_allowed = list()


/obj/item/weapon/rig/proc/getCurrentGlasses()
	if(wearer && visor && visor && visor.vision && visor.vision.glasses && (!helmet || (wearer.head && helmet == wearer.head)))
		return visor.vision.glasses

/obj/item/weapon/rig/examine()
	usr << "This is \icon[src][src.name]."
	usr << "[src.desc]"
	if(wearer)
		for(var/obj/item/piece in list(helmet,gloves,chest,boots))
			if(!piece || piece.loc != wearer)
				continue
			usr << "\icon[piece] \The [piece] [piece.gender == PLURAL ? "are" : "is"] deployed."

	if(src.loc == usr)
		usr << "The maintenance panel is [open ? "open" : "closed"]."
		usr << "Hardsuit systems are [offline ? "<font color='red'>offline</font>" : "<font color='green'>online</font>"]."

/obj/item/weapon/rig/New()
	..()

	item_state = icon_state
	wires = new(src)

	//Add on any extra items allowed into suit storage
	if (extra_allowed.len)
		allowed |= extra_allowed

	if((!req_access || !req_access.len) && (!req_one_access || !req_one_access.len))
		locked = 0

	spark_system = new()
	spark_system.set_up(5, 0, src)
	spark_system.attach(src)

	START_PROCESSING(SSobj, src)



	// Create and initialize our various segments.
	if(cell_type)
		cell = new cell_type(src)
	if(air_type)
		air_supply = new air_type(src)
	if(glove_type)
		gloves = new glove_type(src)
		verbs |= /obj/item/weapon/rig/proc/toggle_gauntlets
	if(helm_type)
		helmet = new helm_type(src)
		verbs |= /obj/item/weapon/rig/proc/toggle_helmet
	if(boot_type)
		boots = new boot_type(src)
		verbs |= /obj/item/weapon/rig/proc/toggle_boots
	if(chest_type)
		chest = new chest_type(src)
		chest.equip_delay = 0
		if(allowed)
			chest.allowed = allowed
		chest.slowdown = offline_slowdown
		verbs |= /obj/item/weapon/rig/proc/toggle_chest

	if(initial_modules && initial_modules.len)
		for(var/path in initial_modules)
			var/obj/item/rig_module/module = new path(src)
			install(module)

	for(var/obj/item/piece in list(gloves,helmet,boots,chest))
		if(!istype(piece))
			continue
		piece.canremove = 0
		piece.name = "[suit_type] [initial(piece.name)]"
		piece.desc = "It seems to be part of a [src.name]."
		piece.icon_state = "[initial(icon_state)]"
		piece.min_cold_protection_temperature = min_cold_protection_temperature
		piece.max_heat_protection_temperature = max_heat_protection_temperature
		if(piece.siemens_coefficient > siemens_coefficient) //So that insulated gloves keep their insulation.
			piece.siemens_coefficient = siemens_coefficient
		piece.permeability_coefficient = permeability_coefficient
		piece.unacidable = unacidable
		if(islist(armor)) piece.armor = armor.Copy()

	update_icon(1)

/obj/item/weapon/rig/Destroy()
	for(var/obj/item/piece in list(gloves,boots,helmet,chest))
		QDEL_NULL(piece)
	for(var/a in installed_modules)
		uninstall(a)
	STOP_PROCESSING(SSobj, src)
	QDEL_NULL(wires)
	QDEL_NULL(spark_system)
	return ..()

/obj/item/weapon/rig/proc/suit_is_deployed()
	if(!istype(wearer) || src.loc != wearer || wearer.back != src)
		return 0
	if(helm_type && !(helmet && wearer.head == helmet))
		return 0
	if(glove_type && !(gloves && wearer.gloves == gloves))
		return 0
	if(boot_type && !(boots && wearer.shoes == boots))
		return 0
	if(chest_type && !(chest && wearer.wear_suit == chest))
		return 0
	return 1

/obj/item/weapon/rig/proc/reset()
	offline = 2
	canremove = 1
	active = FALSE
	for(var/obj/item/piece in list(helmet,boots,gloves,chest))
		if(!piece) continue
		piece.icon_state = "[initial(icon_state)]"
		if(airtight)
			piece.item_flags &= ~(STOPPRESSUREDAMAGE|AIRTIGHT)
	update_icon(1)

/obj/item/weapon/rig/proc/toggle_seals(var/mob/initiator,var/instant)

	if(sealing) return

	// Seal toggling can be initiated by the suit AI, too
	if(!wearer)
		initiator << SPAN_DANGER("Cannot toggle suit: The suit is currently not being worn by anyone.")
		return 0

	if(!check_power_cost(wearer))
		return 0



	var/seal_target = !active

	//Only force deploy when we're turning it on, not when removing it
	if (seal_target)
		deploy(wearer,instant)

	var/failed_to_seal

	canremove = 0 // No removing the suit while unsealing.
	sealing = 1

	if(seal_target && !suit_is_deployed())
		wearer.visible_message(SPAN_DANGER("[wearer]'s suit flashes an error light."),SPAN_DANGER("Your suit flashes an error light. It can't function properly without being fully deployed."))
		failed_to_seal = 1

	if(!failed_to_seal)

		if(!instant)
			wearer.visible_message("<font color='blue'>[wearer]'s suit emits a quiet hum as it begins to adjust its seals.</font>","<font color='blue'>With a quiet hum, the suit begins running checks and adjusting components.</font>")
			if(seal_delay && !do_after(wearer,seal_delay, src))
				if(wearer) wearer << SPAN_WARNING("You must remain still while the suit is adjusting the components.")
				failed_to_seal = 1

		if(!wearer)
			failed_to_seal = 1
		else
			for(var/list/piece_data in list(list(wearer.shoes,boots,"boots",boot_type),list(wearer.gloves,gloves,"gloves",glove_type),list(wearer.head,helmet,"helmet",helm_type),list(wearer.wear_suit,chest,"chest",chest_type)))

				var/obj/item/piece = piece_data[1]
				var/obj/item/compare_piece = piece_data[2]
				var/msg_type = piece_data[3]
				var/piece_type = piece_data[4]

				if(!piece || !piece_type)
					continue

				if(!istype(wearer) || !istype(piece) || !istype(compare_piece) || !msg_type)
					if(wearer) wearer << SPAN_WARNING("You must remain still while the suit is adjusting the components.")
					failed_to_seal = 1
					break

				if(!failed_to_seal && wearer.back == src && piece == compare_piece)

					if(seal_delay && !instant && !do_after(wearer,seal_delay,src,needhand=0))
						failed_to_seal = 1

					piece.icon_state = "[initial(icon_state)][seal_target ? "_sealed" : ""]"
					switch(msg_type)
						if("boots")
							wearer << "<font color='blue'>\The [piece] [seal_target ? "seal around your feet" : "relax their grip on your legs"].</font>"
							wearer.update_inv_shoes()
						if("gloves")
							wearer << "<font color='blue'>\The [piece] [seal_target ? "tighten around your fingers and wrists" : "become loose around your fingers"].</font>"
							wearer.update_inv_gloves()
						if("chest")
							wearer << "<font color='blue'>\The [piece] [seal_target ? "cinches tight again your chest" : "releases your chest"].</font>"
							wearer.update_inv_wear_suit()
						if("helmet")
							wearer << "<font color='blue'>\The [piece] hisses [seal_target ? "closed" : "open"].</font>"
							wearer.update_inv_head()
							if(helmet)
								helmet.update_light(wearer)

					//sealed pieces become airtight, protecting against diseases
					if (seal_target)
						piece.armor["bio"] = 100
					else
						piece.armor["bio"] = src.armor["bio"]

				else
					failed_to_seal = 1

		if((wearer && !(istype(wearer) && wearer.back == src)) || (seal_target && !suit_is_deployed()))
			failed_to_seal = 1

	sealing = null

	if(failed_to_seal)
		for(var/obj/item/piece in list(helmet,boots,gloves,chest))
			if(!piece) continue
			piece.icon_state = "[initial(icon_state)][seal_target ? "" : "_sealed"]"
		canremove = !active

		if(airtight)
			update_component_sealed()
		update_icon(1)
		return 0

	// Success!
	active = seal_target
	canremove = !active
	wearer << "<font color='blue'><b>Your entire suit [active ? "tightens around you as the components lock into place" : "loosens as the components relax"].</b></font>"

	if(wearer != initiator)
		initiator << "<font color='blue'>Suit adjustment complete. Suit is now [active ? "unsealed" : "sealed"].</font>"

	if(canremove)
		for(var/obj/item/rig_module/module in installed_modules)
			module.deactivate()
	if(airtight)
		update_component_sealed()
	update_icon(1)

/obj/item/weapon/rig/proc/update_component_sealed()
	for(var/obj/item/piece in list(helmet,boots,gloves,chest))
		if(canremove)
			piece.item_flags &= ~(STOPPRESSUREDAMAGE|AIRTIGHT)
		else
			piece.item_flags |=  (STOPPRESSUREDAMAGE|AIRTIGHT)
	update_icon(1)

/obj/item/weapon/rig/Process()

	// If we've lost any parts, grab them back.
	var/mob/living/M
	for(var/obj/item/piece in list(gloves,boots,helmet,chest))
		if(piece.loc != src && !(wearer && piece.loc == wearer))
			if(isliving(piece.loc))
				M = piece.loc
				M.drop_from_inventory(piece)
			piece.forceMove(src)

	if(!istype(wearer) || loc != wearer || wearer.back != src || canremove || !cell || cell.charge <= 0)
		if(!cell || cell.charge <= 0)
			if(electrified > 0)
				electrified = 0
			if(!offline)
				if(istype(wearer))
					if(!canremove)
						if (offline_slowdown < 3)
							wearer << SPAN_DANGER("Your suit beeps stridently, and suddenly goes dead.")
						else
							wearer << SPAN_DANGER("Your suit beeps stridently, and suddenly you're wearing a leaden mass of metal and plastic composites instead of a powered suit.")
					if(offline_vision_restriction == 1)
						wearer << SPAN_DANGER("The suit optics flicker and die, leaving you with restricted vision.")
					else if(offline_vision_restriction == 2)
						wearer << SPAN_DANGER("The suit optics drop out completely, drowning you in darkness.")
		if(!offline)
			offline = 1
	else
		if(offline)
			offline = 0
			if(istype(wearer) && !wearer.wearing_rig)
				wearer.wearing_rig = src
			chest.slowdown = initial(slowdown)

	if(offline)
		if(offline == 1)
			for(var/obj/item/rig_module/module in installed_modules)
				module.deactivate()
			offline = 2
			chest.slowdown = offline_slowdown
		return

	if(cell && cell.charge > 0 && electrified > 0)
		electrified--

	if(malfunction_delay > 0)
		malfunction_delay--
	else if(malfunctioning)
		malfunctioning--
		malfunction()

	for(var/obj/item/rig_module/module in installed_modules)
		cell.use(module.Process()*10)

/obj/item/weapon/rig/proc/check_power_cost(var/mob/living/user, var/cost, var/use_unconcious, var/obj/item/rig_module/mod, var/user_is_ai)

	if(!istype(user))
		return 0

	var/fail_msg

	if(!user_is_ai)
		var/mob/living/carbon/human/H = user
		if(istype(H) && H.back != src)
			fail_msg = SPAN_WARNING("You must be wearing \the [src] to do this.")
		else if(user.incorporeal_move)
			fail_msg = SPAN_WARNING("You must be solid to do this.")
	if(sealing)
		fail_msg = SPAN_WARNING("The hardsuit is in the process of adjusting seals and cannot be activated.")
	else if(!fail_msg && ((use_unconcious && user.stat > 1) || (!use_unconcious && user.stat)))
		fail_msg = SPAN_WARNING("You are in no fit state to do that.")
	else if(!cell)
		fail_msg = SPAN_WARNING("There is no cell installed in the suit.")
	else if(cost && cell.charge < cost * 10) //TODO: Cellrate?
		fail_msg = SPAN_WARNING("Not enough stored power.")

	if(fail_msg)
		user << "[fail_msg]"
		return 0

	// This is largely for cancelling stealth and whatever.
	if(mod && mod.disruptive)
		for(var/obj/item/rig_module/module in (installed_modules - mod))
			if(module.active && module.disruptable)
				module.deactivate()

	cell.use(cost*10)
	return 1

/obj/item/weapon/rig/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = 1, var/nano_state =GLOB.inventory_state)
	if(!user)
		return

	var/list/data = list()

	if(selected_module)
		data["primarysystem"] = "[selected_module.interface_name]"

	if(src.loc != user)
		data["ai"] = 1

	data["active"] =     "[active]"
	data["sealing"] =   "[src.sealing]"
	data["helmet"] =    (helmet ? "[helmet.name]" : "None.")
	data["gauntlets"] = (gloves ? "[gloves.name]" : "None.")
	data["boots"] =     (boots ?  "[boots.name]" :  "None.")
	data["chest"] =     (chest ?  "[chest.name]" :  "None.")

	data["charge"] =       cell ? round(cell.charge,1) : 0
	data["maxcharge"] =    cell ? cell.maxcharge : 0
	data["chargestatus"] = cell ? Floor((cell.charge/cell.maxcharge)*50) : 0

	data["emagged"] =       subverted
	data["coverlock"] =     locked
	data["interfacelock"] = interface_locked
	data["aicontrol"] =     control_overridden
	data["aioverride"] =    ai_override_enabled
	data["securitycheck"] = security_check_enabled
	data["malf"] =          malfunction_delay


	var/list/module_list = list()
	var/i = 1
	for(var/obj/item/rig_module/module in installed_modules)
		var/list/module_data = list(
			"index" =             i,
			"name" =              "[module.interface_name]",
			"desc" =              "[module.interface_desc]",
			"can_use" =           "[module.usable]",
			"can_select" =        "[module.selectable]",
			"can_toggle" =        "[module.toggleable]",
			"is_active" =         "[module.active]",
			"engagecost" =        module.use_power_cost*10,
			"activecost" =        module.active_power_cost*10,
			"passivecost" =       module.passive_power_cost*10,
			"engagestring" =      module.engage_string,
			"activatestring" =    module.activate_string,
			"deactivatestring" =  module.deactivate_string,
			"damage" =            module.damage
			)

		if(module.charges && module.charges.len)

			module_data["charges"] = list()
			var/datum/rig_charge/selected = module.charges[module.charge_selected]
			module_data["chargetype"] = selected ? "[selected.display_name]" : "none"

			for(var/chargetype in module.charges)
				var/datum/rig_charge/charge = module.charges[chargetype]
				module_data["charges"] += list(list("caption" = "[chargetype] ([charge.charges])", "index" = "[chargetype]"))

		module_list += list(module_data)
		i++

	if(module_list.len)
		data["modules"] = module_list

	ui = SSnano.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, ((src.loc != user) ? ai_interface_path : interface_path), interface_title, 480, 550, state = nano_state)
		ui.set_initial_data(data)
		ui.open()
		ui.set_auto_update(1)

/obj/item/weapon/rig/update_icon(var/update_mob_icon)

	overlays.Cut()
	if(!mob_icon || update_mob_icon)
		var/species_icon = 'icons/mob/rig_back.dmi'
		// Since setting mob_icon will override the species checks in
		// update_inv_wear_suit(), handle species checks here.
		mob_icon = image("icon" = species_icon, "icon_state" = icon_state)

	if(installed_modules.len)
		for(var/obj/item/rig_module/module in installed_modules)
			if(module.suit_overlay)
				chest.overlays += image("icon" = 'icons/mob/rig_modules.dmi', "icon_state" = module.suit_overlay, "dir" = SOUTH)

	if(wearer)
		wearer.update_inv_shoes()
		wearer.update_inv_gloves()
		wearer.update_inv_head()
		wearer.update_inv_wear_suit()
		wearer.update_inv_back()
	return

/obj/item/weapon/rig/proc/check_suit_access(var/mob/living/carbon/human/user)

	if(!security_check_enabled)
		return 1

	if(istype(user))
		if(malfunction_check(user))
			return 0
		if(user.back != src)
			return 0
		else if(!src.allowed(user))
			user << SPAN_DANGER("Unauthorized user. Access denied.")
			return 0

	else if(!ai_override_enabled)
		user << SPAN_DANGER("Synthetic access disabled. Please consult hardware provider.")
		return 0

	return 1

//TODO: Fix Topic vulnerabilities for malfunction and AI override.
/obj/item/weapon/rig/Topic(href,href_list)
	if(!check_suit_access(usr))
		return 0

	if(href_list["toggle_piece"])
		if(ishuman(usr) && (usr.stat || usr.stunned || usr.lying))
			return 0
		toggle_piece(href_list["toggle_piece"], usr)
	else if(href_list["toggle_seals"])
		toggle_seals(usr)
	else if(href_list["interact_module"])

		var/module_index = text2num(href_list["interact_module"])

		if(module_index > 0 && module_index <= installed_modules.len)
			var/obj/item/rig_module/module = installed_modules[module_index]
			switch(href_list["module_mode"])
				if("activate")
					module.activate()
				if("deactivate")
					module.deactivate()
				if("engage")
					module.engage()
				if("select")
					selected_module = module
				if("select_charge_type")
					module.charge_selected = href_list["charge_type"]
	else if(href_list["toggle_ai_control"])
		ai_override_enabled = !ai_override_enabled
		notify_ai("Synthetic suit control has been [ai_override_enabled ? "enabled" : "disabled"].")
	else if(href_list["toggle_suit_lock"])
		if (locked != -1)
			locked = !locked

	usr.set_machine(src)
	src.add_fingerprint(usr)
	return 0

/obj/item/weapon/rig/proc/notify_ai(var/message)
	for(var/obj/item/rig_module/ai_container/module in installed_modules)
		if(module.integrated_ai && module.integrated_ai.client && !module.integrated_ai.stat)
			module.integrated_ai << "[message]"
			. = 1

//Delayed equipping of rigs
/obj/item/weapon/rig/pre_equip(var/mob/user, var/slot)
	if (active)
		//Can't take it off while it's engaged
		return TRUE

	if (slot == rig_wear_slot)
		if(seal_delay > 0)
			user.visible_message(
				SPAN_NOTICE("[user] starts putting on \the [src]..."),
				SPAN_NOTICE("You start putting on \the [src]...")
			)
			if(!do_after(user,seal_delay,src))
				return TRUE //A nonzero return value will cause the equipping operation to fail
	//Delayed unequipping too
	else if (is_worn())
		retract()
		if(seal_delay > 0)
			user.visible_message(
				SPAN_NOTICE("[user] starts taking off \the [src]..."),
				SPAN_NOTICE("You start taking off \the [src]...")
			)
			if(!do_after(user,seal_delay,src))
				return TRUE //A nonzero return value will cause the equipping operation to fail


/obj/item/weapon/rig/equipped(var/mob/user, var/slot)
	..()
	if (slot == rig_wear_slot)
		user.visible_message(
			SPAN_NOTICE("<b>[user] struggles into \the [src].</b>"),
			SPAN_NOTICE("<b>You struggle into \the [src].</b>")
		)
		wearer = user
		wearer.wearing_rig = src
		update_icon()


/obj/item/weapon/rig/proc/toggle_piece(var/piece, var/mob/initiator, var/deploy_mode)

	if(sealing || !cell || !cell.charge)
		return

	if(!istype(wearer) || !wearer.back == src)
		return

	if(initiator == wearer && (usr.stat||usr.paralysis||usr.stunned)) // If the initiator isn't wearing the suit it's probably an AI.
		return

	var/obj/item/check_slot
	var/equip_to
	var/obj/item/clothing/use_obj

	if(!wearer)
		return

	switch(piece)
		if("helmet")
			equip_to = slot_head
			use_obj = helmet
			check_slot = wearer.head
		if("gauntlets")
			equip_to = slot_gloves
			use_obj = gloves
			check_slot = wearer.gloves
		if("boots")
			equip_to = slot_shoes
			use_obj = boots
			check_slot = wearer.shoes
		if("chest")
			equip_to = slot_wear_suit
			use_obj = chest
			check_slot = wearer.wear_suit

	if(use_obj)
		if(check_slot == use_obj && deploy_mode != ONLY_DEPLOY)
			if (active && !(use_obj.retract_while_active))
				wearer << SPAN_DANGER("The [use_obj] is locked in place while [src] is active. You must deactivate it first!")
				return

			var/mob/living/carbon/human/holder

			if(use_obj)
				holder = use_obj.loc
				if(istype(holder))
					if(use_obj && check_slot == use_obj)
						use_obj.canremove = 1
						if (wearer.unEquip(use_obj, src))
							wearer << "<font color='blue'><b>Your [use_obj.name] [use_obj.gender == PLURAL ? "retract" : "retracts"] swiftly.</b></font>"
						use_obj.canremove = 0


		else if (deploy_mode != ONLY_RETRACT)
			if(check_slot && check_slot == use_obj)
				return

			if(!wearer.equip_to_slot_if_possible(use_obj, equip_to, TRUE)) //Disable_warning
				use_obj.forceMove(src)
				if(check_slot)
					initiator << "<span class='danger'>You are unable to deploy \the [piece] as \the [check_slot] [check_slot.gender == PLURAL ? "are" : "is"] in the way.</span>"
					return
			else
				wearer << "<span class='notice'>Your [use_obj.name] [use_obj.gender == PLURAL ? "deploy" : "deploys"] swiftly.</span>"

	if(piece == "helmet" && helmet)
		helmet.update_light(wearer)

/obj/item/weapon/rig/proc/deploy(mob/M,var/sealed)

	var/mob/living/carbon/human/H = M

	if(!H || !istype(H)) return

	if(H.back != src)
		return

	if(sealed)
		if(H.head)
			var/obj/item/garbage = H.head
			H.drop_from_inventory(garbage)
			H.head = null
			qdel(garbage)

		if(H.gloves)
			var/obj/item/garbage = H.gloves
			H.drop_from_inventory(garbage)
			H.gloves = null
			qdel(garbage)

		if(H.shoes)
			var/obj/item/garbage = H.shoes
			H.drop_from_inventory(garbage)
			H.shoes = null
			qdel(garbage)

		if(H.wear_suit)
			var/obj/item/garbage = H.wear_suit
			H.drop_from_inventory(garbage)
			H.wear_suit = null
			qdel(garbage)

	for(var/piece in list("helmet","gauntlets","chest","boots"))
		toggle_piece(piece, H, ONLY_DEPLOY)

/obj/item/weapon/rig/dropped(var/mob/user)
	..()
	remove()

/obj/item/weapon/rig/proc/retract()
	if (wearer)
		for(var/piece in list("helmet","gauntlets","chest","boots"))
			toggle_piece(piece, wearer, ONLY_RETRACT)

/obj/item/weapon/rig/proc/remove()
	retract()
	if(wearer)
		wearer.wearing_rig = null
		wearer = null

//Todo
/obj/item/weapon/rig/proc/malfunction()
	return 0

/obj/item/weapon/rig/emp_act(severity_class)
	//set malfunctioning
	if(emp_protection < 30) //for ninjas, really.
		malfunctioning += 10
		if(malfunction_delay <= 0)
			malfunction_delay = max(malfunction_delay, round(30/severity_class))

	//drain some charge
	if(cell) cell.emp_act(severity_class + 15)

	//possibly damage some modules
	take_hit((100/severity_class), "electrical pulse", 1)

/obj/item/weapon/rig/proc/shock(mob/user)
	if (!user)
		return 0

	if (electrocute_mob(user, cell, src)) //electrocute_mob() handles removing charge from the cell, no need to do that here.
		spark_system.start()
		if(user.stunned)
			return 1
	return 0

/obj/item/weapon/rig/proc/take_hit(damage, source, is_emp=0)

	if(!installed_modules.len)
		return

	var/chance
	if(!is_emp)
		chance = 2*max(0, damage - (chest? chest.breach_threshold : 0))
	else
		//Want this to be roughly independant of the number of modules, meaning that X emp hits will disable Y% of the suit's modules on average.
		//that way people designing hardsuits don't have to worry (as much) about how adding that extra module will affect emp resiliance by 'soaking' hits for other modules
		chance = 2*max(0, damage - emp_protection)*min(installed_modules.len/15, 1)

	if(!prob(chance))
		return

	//deal addition damage to already damaged module first.
	//This way the chances of a module being disabled aren't so remote.
	var/list/valid_modules = list()
	var/list/damaged_modules = list()
	for(var/obj/item/rig_module/module in installed_modules)
		if(module.damage < 2)
			valid_modules |= module
			if(module.damage > 0)
				damaged_modules |= module

	var/obj/item/rig_module/dam_module = null
	if(damaged_modules.len)
		dam_module = pick(damaged_modules)
	else if(valid_modules.len)
		dam_module = pick(valid_modules)

	if(!dam_module) return

	dam_module.damage++

	if(!source)
		source = "hit"

	if(wearer)
		if(dam_module.damage >= 2)
			wearer << SPAN_DANGER("The [source] has disabled your [dam_module.interface_name]!")
		else
			wearer << SPAN_WARNING("The [source] has damaged your [dam_module.interface_name]!")
	dam_module.deactivate()

/obj/item/weapon/rig/proc/malfunction_check(var/mob/living/carbon/human/user)
	if(malfunction_delay)
		if(offline)
			user << SPAN_DANGER("The suit is completely unresponsive.")
		else
			user << SPAN_DANGER("ERROR: Hardware fault. Rebooting interface...")
		return 1
	return 0

/obj/item/weapon/rig/proc/ai_can_move_suit(var/mob/user, var/check_user_module = 0, var/check_for_ai = 0)

	if(check_for_ai)
		if(!(locate(/obj/item/rig_module/ai_container) in contents))
			return 0
		var/found_ai
		for(var/obj/item/rig_module/ai_container/module in contents)
			if(module.damage >= 2)
				continue
			if(module.integrated_ai && module.integrated_ai.client && !module.integrated_ai.stat)
				found_ai = 1
				break
		if(!found_ai)
			return 0

	if(check_user_module)
		if(!user || !user.loc || !user.loc.loc)
			return 0
		var/obj/item/rig_module/ai_container/module = user.loc.loc
		if(!istype(module) || module.damage >= 2)
			user << SPAN_WARNING("Your host module is unable to interface with the suit.")
			return 0

	if(offline || !cell || !cell.charge || locked_down)
		if(user) user << SPAN_WARNING("Your host rig is unpowered and unresponsive.")
		return 0
	if(!wearer || wearer.back != src)
		if(user) user << SPAN_WARNING("Your host rig is not being worn.")
		return 0
	if(!wearer.stat && !control_overridden && !ai_override_enabled)
		if(user) user << SPAN_WARNING("You are locked out of the suit servo controller.")
		return 0
	return 1

/obj/item/weapon/rig/proc/force_rest(var/mob/user)
	if(!ai_can_move_suit(user, check_user_module = 1))
		return
	wearer.lay_down()
	user << "<span class='notice'>\The [wearer] is now [wearer.resting ? "resting" : "getting up"].</span>"

/obj/item/weapon/rig/proc/forced_move(var/direction, var/mob/user)

	// Why is all this shit in client/Move()? Who knows?
	if (wearer_move_delayer.isBlocked())
		return

	if(!wearer || !wearer.loc || !ai_can_move_suit(user, check_user_module = 1))
		return

	//This is sota the goto stop mobs from moving var
	if(wearer.transforming || !wearer.canmove)
		return

	if(locate(/obj/effect/stop/, wearer.loc))
		for(var/obj/effect/stop/S in wearer.loc)
			if(S.victim == wearer)
				return

	if(!wearer.lastarea)
		wearer.lastarea = get_area(wearer.loc)

	if((istype(wearer.loc, /turf/space)) || (wearer.lastarea.has_gravity == 0))
		if(!wearer.Allow_Spacemove(0))
			return 0

	if(malfunctioning)
		direction = pick(cardinal)

	// Inside an object, tell it we moved.
	if(isobj(wearer.loc) || ismob(wearer.loc))
		var/atom/O = wearer.loc
		return O.relaymove(wearer, direction)

	if(isturf(wearer.loc))
		if(wearer.restrained())//Why being pulled while cuffed prevents you from moving
			for(var/mob/M in range(wearer, 1))
				if(M.pulling == wearer)
					if(!M.restrained() && M.stat == 0 && M.canmove && wearer.Adjacent(M))
						user << SPAN_NOTICE("Your host is restrained! They can't move!")
						return 0
					else
						M.stop_pulling()

	if(wearer.pinned.len)
		src << "<span class='notice'>Your host is pinned to a wall by [wearer.pinned[1]]</span>!"
		return 0

	if(istype(wearer.buckled, /obj/vehicle))
		// manually set move_delay for vehicles so we don't inherit any mob movement penalties
		// specific vehicle move delays are set in code\modules\vehicles\vehicle.dm
		wearer_move_delayer.setDelayMin(1)
		return wearer.buckled.relaymove(wearer, direction)

	var/delay = ai_controlled_move_delay
	wearer_move_delayer.setDelayMin(delay)

	if(istype(wearer.machine, /obj/machinery))
		if(wearer.machine.relaymove(wearer, direction))
			return

	if(wearer.pulledby || wearer.buckled) // Wheelchair driving!
		if(istype(wearer.loc, /turf/space))
			return // No wheelchair driving in space
		if(istype(wearer.pulledby, /obj/structure/bed/chair/wheelchair))
			return wearer.pulledby.relaymove(wearer, direction)
		else if(istype(wearer.buckled, /obj/structure/bed/chair/wheelchair))
			if(ishuman(wearer.buckled))
				var/obj/item/organ/external/l_hand = wearer.get_organ(BP_L_ARM)
				var/obj/item/organ/external/r_hand = wearer.get_organ(BP_R_ARM)
				if((!l_hand || (l_hand.status & ORGAN_DESTROYED)) && (!r_hand || (r_hand.status & ORGAN_DESTROYED)))
					return // No hands to drive your chair? Tough luck!
			wearer_move_delayer.addDelay(2)
			return wearer.buckled.relaymove(wearer,direction)

	cell.use(200) //Arbitrary, TODO
	step_glide(wearer, direction, DELAY2GLIDESIZE(delay))

// This returns the rig if you are contained inside one, but not if you are wearing it
/atom/proc/get_rig()
	if(loc)
		return loc.get_rig()
	return null

/obj/item/weapon/rig/get_rig()
	return src

/mob/living/carbon/human/get_rig()
	return back


//Used in random rig spawning for cargo
//Randomly deletes modules
/obj/item/weapon/rig/proc/lose_modules(var/probability)
	for(var/obj/item/rig_module/module in installed_modules)
		if (probability)
			qdel(module)


//Fiddles with some wires to possibly make the suit malfunction a little
/obj/item/weapon/rig/proc/misconfigure(var/probability)
	if (prob(probability))
		wires.UpdatePulsed(RIG_SECURITY)//Fiddle with access
	if (prob(probability))
		wires.UpdatePulsed(RIG_AI_OVERRIDE)//frustrate the AI
	if (prob(probability))
		wires.UpdateCut(RIG_SYSTEM_CONTROL)//break the suit
	if (prob(probability))
		wires.UpdatePulsed(RIG_INTERFACE_LOCK)
	if (prob(probability))
		wires.UpdateCut(RIG_INTERFACE_SHOCK)
	if (prob(probability))
		subverted = 1

//Drains, rigs or removes the cell
/obj/item/weapon/rig/proc/sabotage_cell()
	if (!cell)
		return

	if (prob(50))
		cell.charge = rand(0, cell.charge*0.5)
	else if (prob(15))
		cell.rigged = 1
	else
		cell = null

//Depletes or removes the airtank
/obj/item/weapon/rig/proc/sabotage_tank()
	if (!air_supply)
		return

	if (prob(70))
		air_supply.remove_air(air_supply.air_contents.total_moles)
	else
		QDEL_NULL(air_supply)

#undef ONLY_DEPLOY
#undef ONLY_RETRACT
#undef SEAL_DELAY
