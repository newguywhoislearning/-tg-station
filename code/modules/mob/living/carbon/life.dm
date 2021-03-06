/mob/living/carbon/Life()
	set invisibility = 0
	set background = BACKGROUND_ENABLED

	if (notransform)
		return
	if(!loc)
		return

	if(..())
		. = 1
		for(var/datum/organ/internal/OR in get_all_internal_organs())
			if(OR && OR.exists())
				var/obj/item/organ/internal/O = OR.organitem
				O.on_life()

	//Updates the number of stored chemicals for powers
	handle_changeling()



///////////////
// BREATHING //
///////////////

//Start of a breath chain, calls breathe()
/mob/living/carbon/handle_breathing()
	if(SSmob.times_fired%4==2 || failed_last_breath)
		breathe() //Breathe per 4 ticks, unless suffocating
	else
		if(istype(loc, /obj/))
			var/obj/location_as_object = loc
			location_as_object.handle_internal_lifeform(src,0)

//Second link in a breath chain, calls check_breath()
/mob/living/carbon/proc/breathe()
	if(reagents && reagents.has_reagent("lexorin"))
		return
	if(istype(loc, /obj/machinery/atmospherics/components/unary/cryo_cell))
		return

	var/datum/gas_mixture/environment
	if(loc)
		environment = loc.return_air()

	var/datum/gas_mixture/breath

	if(health <= config.health_threshold_crit)
		losebreath++

	//Suffocate
	if(losebreath > 0)
		losebreath--
		if(prob(10))
			spawn emote("gasp")
		if(istype(loc, /obj/))
			var/obj/loc_as_obj = loc
			loc_as_obj.handle_internal_lifeform(src,0)
	else
		//Breathe from internal
		breath = get_breath_from_internal(BREATH_VOLUME)

		if(!breath)

			if(isobj(loc)) //Breathe from loc as object
				var/obj/loc_as_obj = loc
				breath = loc_as_obj.handle_internal_lifeform(src, BREATH_VOLUME)

			else if(isturf(loc)) //Breathe from loc as turf
				var/breath_moles = 0
				if(environment)
					breath_moles = environment.total_moles()*BREATH_PERCENTAGE

				breath = loc.remove_air(breath_moles)

				//Harmful gasses
				if(!has_smoke_protection())
					for(var/obj/effect/effect/smoke/chem/S in range(1, src))
						if(S.reagents.total_volume && S.lifetime)
							var/fraction = 1/initial(S.lifetime)
							S.reagents.reaction(src,INGEST, fraction)
							var/amount = round(S.reagents.total_volume*fraction,0.1)
							S.reagents.copy_to(src, amount)
							S.lifetime--

		else //Breathe from loc as obj again
			if(istype(loc, /obj/))
				var/obj/loc_as_obj = loc
				loc_as_obj.handle_internal_lifeform(src,0)

	check_breath(breath)

	if(breath)
		loc.assume_air(breath)

/mob/living/carbon/proc/has_smoke_protection()
	return 0


//Third link in a breath chain, calls handle_breath_temperature()
/mob/living/carbon/proc/check_breath(datum/gas_mixture/breath)
	if((status_flags & GODMODE))
		return

	//CRIT
	if(!breath || (breath.total_moles() == 0))
		if(reagents.has_reagent("inaprovaline"))
			return
		adjustOxyLoss(1)
		failed_last_breath = 1
		throw_alert("oxy")

		return 0

	var/safe_oxy_min = 16
	var/safe_co2_max = 10
	var/safe_tox_max = 0.05
	var/SA_para_min = 1
	var/SA_sleep_min = 5
	var/oxygen_used = 0
	var/breath_pressure = (breath.total_moles()*R_IDEAL_GAS_EQUATION*T20C)/BREATH_VOLUME

	var/O2_partialpressure = (breath.oxygen/breath.total_moles())*breath_pressure
	var/Toxins_partialpressure = (breath.toxins/breath.total_moles())*breath_pressure
	var/CO2_partialpressure = (breath.carbon_dioxide/breath.total_moles())*breath_pressure


	//OXYGEN
	if(O2_partialpressure < safe_oxy_min) //Not enough oxygen
		if(prob(20))
			spawn(0)
				emote("gasp")
		if(O2_partialpressure > 0)
			var/ratio = safe_oxy_min/O2_partialpressure
			adjustOxyLoss(min(5*ratio, 3))
			failed_last_breath = 1
			oxygen_used = breath.oxygen*ratio/6
		else
			adjustOxyLoss(3)
			failed_last_breath = 1
		throw_alert("oxy")

	else //Enough oxygen
		failed_last_breath = 0
		adjustOxyLoss(-5)
		oxygen_used = breath.oxygen/6
		clear_alert("oxy")

	breath.oxygen -= oxygen_used
	breath.carbon_dioxide += oxygen_used

	//CARBON DIOXIDE
	if(CO2_partialpressure > safe_co2_max)
		if(!co2overloadtime)
			co2overloadtime = world.time
		else if(world.time - co2overloadtime > 120)
			Paralyse(3)
			adjustOxyLoss(3)
			if(world.time - co2overloadtime > 300)
				adjustOxyLoss(8)
		if(prob(20))
			spawn(0) emote("cough")

	else
		co2overloadtime = 0

	//TOXINS/PLASMA
	if(Toxins_partialpressure > safe_tox_max)
		var/ratio = (breath.toxins/safe_tox_max) * 10
		if(reagents)
			reagents.add_reagent("plasma", Clamp(ratio, MIN_PLASMA_DAMAGE, MAX_PLASMA_DAMAGE))
		throw_alert("tox_in_air")
	else
		clear_alert("tox_in_air")

	//TRACE GASES
	if(breath.trace_gases.len)
		for(var/datum/gas/sleeping_agent/SA in breath.trace_gases)
			var/SA_partialpressure = (SA.moles/breath.total_moles())*breath_pressure
			if(SA_partialpressure > SA_para_min)
				Paralyse(3)
				if(SA_partialpressure > SA_sleep_min)
					sleeping = max(sleeping+2, 10)
			else if(SA_partialpressure > 0.01)
				if(prob(20))
					spawn(0) emote(pick("giggle","laugh"))

	//BREATH TEMPERATURE
	handle_breath_temperature(breath)

	return 1

//Fourth and final link in a breath chain
/mob/living/carbon/proc/handle_breath_temperature(datum/gas_mixture/breath)


/mob/living/carbon/proc/get_breath_from_internal(volume_needed)
	if(internal)
		if (!contents.Find(internal))
			internal = null
		if (!wear_mask || !(wear_mask.flags & MASKINTERNALS) )
			internal = null
		if(internal)
			if (internals)
				internals.icon_state = "internal1"
			return internal.remove_air_volume(volume_needed)
		else
			if (internals)
				internals.icon_state = "internal0"
	return


/mob/living/carbon/proc/handle_changeling()
	return

/mob/living/carbon/handle_mutations_and_radiation()
	if(radiation)

		switch(radiation)
			if(0 to 50)
				radiation--
				if(prob(25))
					adjustToxLoss(1)
					updatehealth()

			if(50 to 75)
				radiation -= 2
				adjustToxLoss(1)
				if(prob(5))
					radiation -= 5
				updatehealth()

			if(75 to 100)
				radiation -= 3
				adjustToxLoss(3)
				updatehealth()

		radiation = Clamp(radiation, 0, 100)


/mob/living/carbon/handle_chemicals_in_body()
	if(reagents)
		reagents.metabolize(src)

	if(drowsyness)
		drowsyness--
		eye_blurry = max(2, eye_blurry)
		if(prob(5))
			sleeping += 1
			Paralyse(5)

	confused = max(0, confused - 1)
	// decrement dizziness counter, clamped to 0
	if(resting)
		dizziness = max(0, dizziness - 5)
		jitteriness = max(0, jitteriness - 5)
	else
		dizziness = max(0, dizziness - 1)
		jitteriness = max(0, jitteriness - 1)

	updatehealth()
	return

/mob/living/carbon/handle_blood()
	return

/mob/living/carbon/handle_random_events()
	return

/mob/living/carbon/handle_environment(var/datum/gas_mixture/environment)
	return

/mob/living/carbon/handle_stomach()
	spawn(0)
		for(var/mob/living/M in stomach_contents)
			if(M.loc != src)
				stomach_contents.Remove(M)
				continue
			if(istype(M, /mob/living/carbon) && stat != 2)
				if(M.stat == 2)
					M.death(1)
					stomach_contents.Remove(M)
					qdel(M)
					continue
				if(SSmob.times_fired%3==1)
					if(!(M.status_flags & GODMODE))
						M.adjustBruteLoss(5)
					nutrition += 10

/mob/living/carbon/handle_regular_status_updates()

	if(stat == DEAD)
		eye_blind = max(eye_blind, 1)
		silent = 0
	else
		updatehealth()
		if(health <= config.health_threshold_dead)
			death()
			eye_blind = max(eye_blind, 1)
			silent = 0
			return 1
		else if(organsystem)
			var/datum/organ/B = get_organ("brain")
			if(!(B && B.exists()))
				death()
				eye_blind = max(eye_blind, 1)
				silent = 0
				return 1

		if(getOxyLoss() > 50 || health <= config.health_threshold_crit)
			Paralyse(3)
			stat = UNCONSCIOUS

		if(paralysis)
			AdjustParalysis(-1)
		else if(sleeping)
			handle_dreams()
			adjustStaminaLoss(-10)
			sleeping = max(sleeping-1, 0)
			stat = UNCONSCIOUS
			if( prob(10) && health && !hal_crit )
				spawn(0)
					emote("snore")

		else if (status_flags & FAKEDEATH)
			stat = UNCONSCIOUS

		else
			stat = CONSCIOUS

		handle_disabilities()

		//Dizziness
		if(dizziness)
			var/client/C = client
			var/pixel_x_diff = 0
			var/pixel_y_diff = 0
			var/temp
			var/saved_dizz = dizziness
			dizziness = max(dizziness-1, 0)
			if(C)
				var/oldsrc = src
				var/amplitude = dizziness*(sin(dizziness * 0.044 * world.time) + 1) / 70 // This shit is annoying at high strength
				src = null
				spawn(0)
					if(C)
						temp = amplitude * sin(0.008 * saved_dizz * world.time)
						pixel_x_diff += temp
						C.pixel_x += temp
						temp = amplitude * cos(0.008 * saved_dizz * world.time)
						pixel_y_diff += temp
						C.pixel_y += temp
						sleep(3)
						if(C)
							temp = amplitude * sin(0.008 * saved_dizz * world.time)
							pixel_x_diff += temp
							C.pixel_x += temp
							temp = amplitude * cos(0.008 * saved_dizz * world.time)
							pixel_y_diff += temp
							C.pixel_y += temp
						sleep(3)
						if(C)
							C.pixel_x -= pixel_x_diff
							C.pixel_y -= pixel_y_diff
				src = oldsrc

		//Jitteryness
		if(jitteriness)
			do_jitter_animation(jitteriness)
			jitteriness = max(jitteriness-1, 0)

		//Other

		if(stuttering)
			stuttering = max(stuttering-1, 0)

		if(slurring)
			slurring = max(slurring-1,0)

		if(silent)
			silent = max(silent-1, 0)

		if(druggy)
			druggy = max(druggy-1, 0)

		if(stunned)
			stunned = max(stunned-1,0)
			if(!stunned)
				update_canmove()

		if(weakened)
			weakened = max(weakened-1,0)
			if(!weakened)
				update_canmove()

		if(hallucination)
			spawn handle_hallucinations()

			if(hallucination<=2)
				hallucination = 0
			else
				hallucination -= 2

		else
			for(var/atom/a in hallucinations)
				qdel(a)

		CheckStamina()
	return 1

/mob/living/carbon/handle_disabilities()
	//Eyes
	if(stat)
		if(config && config.critfullblind)
			eye_blind = max(eye_blind, 5)
		eye_covered = max(eye_covered, 5)
	if(!(disabilities & BLIND))	//blindness from disability or unconsciousness doesn't get better on its own
		if(eye_blind)			//blindness, heals slowly over time
			eye_blind = max(eye_blind-1,0)
		else if(eye_covered)			//partially blind eyes heal slowly
			eye_covered = max(eye_covered-1, 0)
		else if(eye_blurry)			//blurry eyes heal slowly
			eye_blurry = max(eye_blurry-1, 0)
	else
		eye_covered = max(eye_covered,1) //Force blindness if user is actually blind
	//Ears
	if(disabilities & DEAF)		//disabled-deaf, doesn't get better on its own
		setEarDamage(-1, max(ear_deaf, 1))
	else
		// deafness heals slowly over time, unless ear_damage is over 100
		if(ear_damage < 100)
			adjustEarDamage(-0.05,-1)


//this handles hud updates. Calles update_vision() and handle_hud_icons()
/mob/living/carbon/handle_regular_hud_updates()
	if(!client)	return 0


/mob/living/carbon/handle_regular_hud_updates()
	if(!client)
		return 0
	if(stat == UNCONSCIOUS && health <= config.health_threshold_crit)
		var/severity = 0
		switch(health)
			if(-20 to -10) severity = 1
			if(-30 to -20) severity = 2
			if(-40 to -30) severity = 3
			if(-50 to -40) severity = 4
			if(-60 to -50) severity = 5
			if(-70 to -60) severity = 6
			if(-80 to -70) severity = 7
			if(-90 to -80) severity = 8
			if(-95 to -90) severity = 9
			if(-INFINITY to -95) severity = 10
		overlay_fullscreen("crit", /obj/screen/fullscreen/crit, severity)
	else
		clear_fullscreen("crit")
		if(oxyloss)
			var/severity = 0
			switch(oxyloss)
				if(10 to 20) severity = 1
				if(20 to 25) severity = 2
				if(25 to 30) severity = 3
				if(30 to 35) severity = 4
				if(35 to 40) severity = 5
				if(40 to 45) severity = 6
				if(45 to INFINITY) severity = 7
			overlay_fullscreen("oxy", /obj/screen/fullscreen/oxy, severity)
		else
			clear_fullscreen("oxy")
		//Fire and Brute damage overlay (BSSR)
		var/hurtdamage = src.getBruteLoss() + src.getFireLoss() + damageoverlaytemp
		damageoverlaytemp = 0 // We do this so we can detect if someone hits us or not.
		if(hurtdamage)
			var/severity = 0
			switch(hurtdamage)
				if(5 to 15) severity = 1
				if(15 to 30) severity = 2
				if(30 to 45) severity = 3
				if(45 to 70) severity = 4
				if(70 to 85) severity = 5
				if(85 to INFINITY) severity = 6
			overlay_fullscreen("brute", /obj/screen/fullscreen/brute, severity)
		else
			clear_fullscreen("brute")
	..()
	return 1

/mob/living/carbon/handle_hud_icons()
	return

/mob/living/carbon/handle_hud_icons_health()
	if(healths)
		if (stat != DEAD)
			switch(health)
				if(100 to INFINITY)
					healths.icon_state = "health0"
				if(80 to 100)
					healths.icon_state = "health1"
				if(60 to 80)
					healths.icon_state = "health2"
				if(40 to 60)
					healths.icon_state = "health3"
				if(20 to 40)
					healths.icon_state = "health4"
				if(0 to 20)
					healths.icon_state = "health5"
				else
					healths.icon_state = "health6"
		else
			healths.icon_state = "health7"

/mob/living/carbon/proc/handle_heart()
	return


/mob/living/carbon/update_sight()

	if(stat == DEAD)
		sight |= SEE_TURFS
		sight |= SEE_MOBS
		sight |= SEE_OBJS
		see_in_dark = 8
		see_invisible = SEE_INVISIBLE_LEVEL_TWO
	else
		if(!(SEE_TURFS & permanent_sight_flags))
			sight &= ~SEE_TURFS
		if(!(SEE_MOBS & permanent_sight_flags))
			sight &= ~SEE_MOBS
		if(!(SEE_OBJS & permanent_sight_flags))
			sight &= ~SEE_OBJS
		if(remote_view)
			sight |= SEE_TURFS
			sight |= SEE_MOBS
			sight |= SEE_OBJS
		see_in_dark = (sight == SEE_TURFS|SEE_MOBS|SEE_OBJS) ? 8 : 2  //Xray flag combo
		see_invisible = SEE_INVISIBLE_LIVING
		if(see_override)
			see_invisible = see_override


/mob/living/carbon/proc/natural_bodytemperature_stabilization(temperature_cold = BODYTEMP_COLD_DAMAGE_LIMIT, temperature_default = 310.15, temperature_hot = BODYTEMP_HEAT_DAMAGE_LIMIT)
	var/body_temperature_difference = temperature_default - bodytemperature
	//For some reason switch(bodytemperature) doesn't seem to work
	if(bodytemperature <= temperature_cold) //260.15 is temperature_default - 50, the temperature where you start to feel effects.
		if(nutrition >= 2) //If we are very, very cold we'll use up quite a bit of nutriment to heat us up.
			nutrition -= 2
		bodytemperature += max((body_temperature_difference * metabolism_efficiency / BODYTEMP_AUTORECOVERY_DIVISOR), BODYTEMP_AUTORECOVERY_MINIMUM)
	else if(bodytemperature <= temperature_default)
		bodytemperature += max(body_temperature_difference * metabolism_efficiency / BODYTEMP_AUTORECOVERY_DIVISOR, min(body_temperature_difference, BODYTEMP_AUTORECOVERY_MINIMUM/4))
	else if(bodytemperature < temperature_hot)
		bodytemperature += min(body_temperature_difference * metabolism_efficiency / BODYTEMP_AUTORECOVERY_DIVISOR, max(body_temperature_difference, -BODYTEMP_AUTORECOVERY_MINIMUM/4))
	else //360.15 is temperature_default + 50, the temperature where you start to feel effects.
		//We totally need a sweat system cause it totally makes sense...~
		bodytemperature += min((body_temperature_difference / BODYTEMP_AUTORECOVERY_DIVISOR), -BODYTEMP_AUTORECOVERY_MINIMUM)	//We're dealing with negative numbers


/mob/living/carbon/handle_actions()
	..()
	if(organsystem)
		for(var/datum/organ/org in get_all_internal_organs())
			give_action_button(org.organitem)	//Recursion isn't needed in the new organsystem
		var/datum/organ/cavity/CAV = get_organ("cavity")
		if(CAV && CAV.exists() && !isorgan(CAV.organitem))	//Last one's there so you can't just cavity implant cybernetic implants
			give_action_button(CAV.organitem)