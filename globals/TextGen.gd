extends Node


const DAMAGE_DISPLAY_NAMES: PoolStringArray = PoolStringArray([
	"Typeless", "Light", "H.E.Particle", "Piercing", "Impact", "EM.Field", \
	"Gravity", "Antimatter", "Hot Matter", 'Psionic'
])

var price_callbacks: Array = []
var cached_page_titles: Dictionary = {}

func add_price_callback(o: Object):
	price_callbacks.append(o)

func remove_price_callback(o: Object):
	price_callbacks.erase(o)

func price_text_for_ship_design(design) -> String:
	# design is a Universe.ShipDesign
	for cb in price_callbacks:
		if cb.has_method('price_text_for_ship_design'):
			var price_text=cb.price_text_for_ship_design(design)
			if price_text:
				return price_text
	return ''

func price_text_for_page(help_page_id) -> String:
	for cb in price_callbacks:
		if cb and cb.has_method('price_text_for_page'):
			var price_text=cb.price_text_for_page(help_page_id)
			if price_text:
				return price_text
	return ''

func make_cell(key,value) -> String:
	return '[cell]'+key+'[/cell][cell]'+str(value)+'[/cell]'

func make_cell3(one,two,three) -> String:
	return '[cell]'+str(one)+'[/cell][cell]'+str(two)+'[/cell][cell]'+str(three)+'[/cell]'

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,str(round(maxval))+' (+'+str(stepify(repairval,.1))+'/s)')
	elif repairval<0:
		return make_cell(key,str(round(maxval))+' ('+str(stepify(repairval,.1))+'/s)')
	return make_cell(key,maxval)

func get_bbcode_for_ship_table(weapon_stats) -> String:
	return '[b]'+weapon_stats['name'].capitalize() + \
		':[/b] {ref '+weapon_stats['help_page']+'}\n' + \
		make_weapon_bbcode(weapon_stats)

func approximate_range(weapon_stats) -> float:
	if weapon_stats['projectile_drag']>0 and weapon_stats['projectile_thrust']>0:
		return max(weapon_stats['initial_velocity'],
			weapon_stats['projectile_thrust']/weapon_stats['projectile_drag']) \
			*max(1.0/60,weapon_stats['projectile_lifetime'])
	return weapon_stats['initial_velocity']*max(1.0/60,weapon_stats['projectile_lifetime'])

func plus_minus(number):
	return ( ('-' if number<0 else '+') + str(abs(number)) )

func add_max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,plus_minus(maxval)+' ('+plus_minus(repairval)+'/s)')
	return make_cell(key,plus_minus(maxval))

func make_row3(one,two,three):
	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]'

func make_row4(one,two,three,four):
	return '[cell]'+str(one)+'[/cell][cell]  [/cell][cell]'+str(two) \
		+'[/cell][cell]  [/cell][cell]'+str(three)+'[/cell]' \
		+'[cell]  [/cell][cell]'+str(four)+'[/cell]'

func make_system_product_hover_info(item_name,mine,here,display_name,price) -> String:
	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
	var MASS_INDEX = Commodities.Products.MASS_INDEX
	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=7]'
	s+=make_row4('  ','[b]Here[/b]','[b]At '+display_name+'[/b]','[b]Difference[/b]')
	s+=make_row4('Price',here[VALUE_INDEX],price,price-here[VALUE_INDEX])
	s+=make_row4('Mass per',here[MASS_INDEX],' ',' ')
	s+=make_row4('Available',here[QUANTITY_INDEX],' ',' ')
	s+=make_row4('In cargo',mine[QUANTITY_INDEX],' ',' ')
	s+=make_row4('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ',' ')
	s+='[/table]\n'
	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
		s+='\nTags:\n'
		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
			s+=' {*} '+here[itag]+'\n'
	return s

func make_product_hover_info(item_name,mine,here,norm) -> String:
	var VALUE_INDEX = Commodities.Products.VALUE_INDEX
	var FINE_INDEX = Commodities.Products.FINE_INDEX
	var QUANTITY_INDEX = Commodities.Products.QUANTITY_INDEX
	var MASS_INDEX = Commodities.Products.MASS_INDEX
	var s: String = '[b]'+item_name.capitalize()+'[/b]\n[table=5]'
	s+=make_row3('  ','[b]Here[/b]','[b]Typical[/b]')
	s+=make_row3('Price',here[VALUE_INDEX],norm[VALUE_INDEX])
	s+=make_row3('Fine',here[FINE_INDEX],norm[FINE_INDEX])
	s+=make_row3('Mass per',here[MASS_INDEX],' ')
	s+=make_row3('Available',here[QUANTITY_INDEX],' ')
	s+=make_row3('In cargo',mine[QUANTITY_INDEX],' ')
	s+=make_row3('Cargo mass',mine[QUANTITY_INDEX]*mine[MASS_INDEX],' ')
	s+='[/table]\n'
	if len(here)>Commodities.Products.FIRST_TAG_INDEX:
		s+='\nTags:\n'
		for itag in range(Commodities.Products.FIRST_TAG_INDEX,len(here)):
			s+=' {*} '+here[itag]+'\n'
	return s

func make_fleet_bbcode(fleet_id, fleet_display_name, design_count: Dictionary) -> String:
	var bbcode: String = '[h2]Fleet '+fleet_display_name+'[/h2]\n'
	if not design_count:
		return bbcode
	var content: String = ''
	var armor: float = 0
	var shields: float = 0
	var structure: float = 0
	var heal_armor: float = 0
	var heal_shields: float = 0
	var heal_structure: float =0
	var dps: float = 0
	var count: int = 0
	var fleet_speed_sum: float = 0
	var fleet_max_speed: float = 0
	var fleet_min_speed: float = INF
	for design_name in design_count:
		var count_this_design: int = design_count[design_name]
		var design = game_state.ship_designs.get_node_or_null(design_name)
		if not design or not count_this_design:
			continue
		var stats = design.get_stats()
		assert(stats.has('empty_mass'))
		var mass = utils.ship_mass(stats)
		
		var n = count_this_design # to make the code shorter
		
		count += n
		
		armor += stats['max_armor']*n
		shields += stats['max_shields']*n
		structure += stats['max_structure']*n
		heal_armor += stats['heal_armor']*n
		heal_shields += stats['heal_shields']*n
		heal_structure += stats['heal_structure']*n
		for weapon in stats['weapons']:
			if weapon['firing_delay']:
				dps += weapon['damage'] / max(1.0/60,weapon['firing_delay'])*n
			else:
				dps += weapon['damage']
		var max_thrust = max(max(stats['reverse_thrust'],stats['thrust']),0)
		var max_speed = max(0,max_thrust/max(1e-9,stats['drag']*mass))
		fleet_max_speed = max(max_speed,fleet_max_speed)
		fleet_min_speed = min(max_speed,fleet_min_speed)
		fleet_speed_sum += fleet_max_speed*n
	
		content += make_ship_bbcode(stats,false,'  [b]x '+str(n)+' in fleet[/b]')
	
	fleet_min_speed = min(fleet_max_speed,fleet_min_speed)
	var fleet_avg_speed = fleet_speed_sum / count
	
	var sep = '[cell]  [/cell]'
	return bbcode \
		+ '[b]Fleet Stats[/b]\n' \
		+ '[table=5]' \
		+ make_cell('Damage:',str(round(dps))+'/s') \
		+sep+ make_cell('Ships:',count) \
		+ max_and_repair('Shields:',shields,heal_shields) \
		+sep+ make_cell('Max Speed:',round(fleet_max_speed*10)/10) \
		+ max_and_repair('Armor:',armor,heal_armor) \
		+sep+ make_cell('Min Speed:',round(fleet_min_speed*10)/10) \
		+ max_and_repair('Structure:',structure,heal_structure) \
		+sep+ make_cell('Avg Speed:',round(fleet_avg_speed*10)/10) \
		+ '[/table]\n' \
		+ '[b]Fleet ID[/b]: [code]'+fleet_id+'[/code]\n\n' \
		+ content

func make_weapon_bbcode(stats: Dictionary) -> String:
		var bbcode: String = '[table=2]'
		
		# Weapon stats:
		bbcode += make_cell('type',stats['mount_type_display'])
		bbcode += make_cell('size',str(stats['item_size_x'])+'x'+str(stats['item_size_y']))
		bbcode += make_cell('weapon mass',stats['weapon_mass'])
		bbcode += make_cell('structure bonus',stats['weapon_structure'])
		if stats['turn_rate']: bbcode += make_cell('turret turn rate',stats['turn_rate'])
		
		# Projectile stats:
		var dps: float = stats['damage']
		var ips: float = stats['impulse']
		if stats['firing_delay']:
			dps /= max(1.0/60.0,stats['firing_delay'])
			ips /= max(1.0/60.0,stats['firing_delay'])
		var shots_per_second = 1.0/max(1.0/60,stats['firing_delay'])
		
		if dps:
			bbcode += make_cell('damage per second',round(dps*10.0)/10.0)
		
		if stats['firing_delay']:
			bbcode += make_cell('shots per second',ceil(shots_per_second))
			bbcode += make_cell('energy per second',stepify(stats['firing_energy']*shots_per_second,0.1))
			bbcode += make_cell('heat per second',stepify(stats['firing_heat']*shots_per_second,0.01))
		else:
			bbcode += make_cell('shots per second','∞ (continuous fire)')
			bbcode += make_cell('energy per second',stepify(stats['firing_energy'],0.1))
			bbcode += make_cell('heat per second',stepify(stats['firing_heat'],.01))
		
		if dps:
			if stats['heat_fraction']:
				bbcode += make_cell('heat damage per second',dps*stats['heat_fraction'])
			if stats['energy_fraction']:
				bbcode += make_cell('energy damage per second',dps*stats['energy_fraction'])
			if stats['thrust_fraction']:
				bbcode += make_cell('thrust damage per second',dps*stats['thrust_fraction'])
		if ips:
			bbcode += make_cell('hit force per second',round(ips*10.0)/10.0)

		if dps:
			if stats['firing_delay']:
				bbcode += make_cell('damage per shot',stats['damage'])
				if stats['heat_fraction']:
					bbcode += make_cell('heat damage per shot',stats['damage']*stats['heat_fraction'])
				if stats['energy_fraction']:
					bbcode += make_cell('energy damage per shot',stats['damage']*stats['energy_fraction'])
				if stats['thrust_fraction']:
					bbcode += make_cell('thrust damage per shot',stats['damage']*stats['thrust_fraction'])
		if ips and stats['firing_delay']:
			bbcode += make_cell('hit force per shot',round(stats['impulse']*10.0/10.0))

		if stats['detonation_range']:
			bbcode += make_cell('detonation range',stats['detonation_range'])
		if stats['blast_radius']:
			bbcode += make_cell('blast radius',stats['blast_radius'])
		bbcode += make_cell('range',round(approximate_range(stats)*100)/100)
		if stats['guided']:
			bbcode += make_cell('guidance','interception' if stats['guidance_uses_velocity'] else 'homing')
			bbcode += make_cell('turn rate',stats['projectile_turn_rate'])
		else:
			bbcode += make_cell('guidance','unguided')

		return bbcode+'[/table]\n'


func help_page_for_scene_path(resource_path) -> String:
	var scene = load(resource_path)
	if scene:
		var state = scene.get_state()
		for i in range(state.get_node_property_count(0)):
			var property_name = state.get_node_property_name(0,i)
			if 'help_page' == property_name:
				var help_page = state.get_node_property_value(0,i)
				if help_page:
					return help_page
	return ''


func title_for_scene_path(resource_path) -> String:
	var title = cached_page_titles.get(resource_path,null)
	if title == null:
		var help_page = help_page_for_scene_path(resource_path)
		title = builtin_commands.Help.page_title(help_page) if help_page else ''
		cached_page_titles[resource_path] = title
	return title

func any_true(array: Array) -> bool:
	for element in array:
		if element:
			return true
	return false

func make_resist_row(index: int,stats: Dictionary,stat_keys: Array,cutoffs: Array,minval: float, maxval: float) -> String:
	var data: Array = []
	for key in stat_keys:
		if stats[key].size()<=index or not stats[key][index]:
			data.append(0)
		else:
			data.append(stats[key][index]*100.0)
	if any_true(data):
		var row: String = '[cell]'+DAMAGE_DISPLAY_NAMES[index]+'[/cell]'
		for datum in data:
			for cut in cutoffs:
				if datum<=cut[0]:
					row += '[cell][color='+cut[1]+']'+str(clamp(round(datum),minval,maxval))+'[/color][/cell]'
					break
		return row
	return ''

func make_resist_table(stats: Dictionary,stat_keys: Array,headings: Array,
		title: String,footer: String,colors: Array,minval: float,maxval: float) -> String:
	var rows: String = ''
	for i in range(len(DAMAGE_DISPLAY_NAMES)):
		rows+=make_resist_row(i,stats,stat_keys,colors,minval,maxval)
	if rows:
		var text = title+'[table='+str(len(stat_keys)+1)+'][cell]Damage[/cell]'
		for heading in headings:
			text+='[cell]'+heading+'[/cell]'
		return text+rows+'[/table]\n'+footer
	return ''

func make_ship_bbcode(ship_stats,with_contents=true,annotation='',show_id=null) -> String:
	var s = ship_stats
	var contents: String = '' #'[b]Contents:[/b]\n'
	if show_id==null:
		show_id = game_state.game_editor_mode
	var dps: float = 0
	var weapon_energy: float = 0
	var weapon_heat: float = 0
	for weapon in ship_stats['weapons']:
		if with_contents:
			contents += '\n[b]'+weapon['name'].capitalize() + \
				':[/b] {ref '+weapon['help_page']+'}\n' + \
				make_weapon_bbcode(weapon)
		var this_weapon_dps = weapon['damage']
		var this_weapon_heat = weapon['firing_heat']
		var this_weapon_energy = weapon['firing_energy']
		if weapon['firing_delay']:
			var delay = max(1.0/60.0,weapon['firing_delay'])
			this_weapon_dps /= delay
			this_weapon_heat /= delay
			this_weapon_energy /= delay
		dps += this_weapon_dps
		weapon_heat += this_weapon_heat
		weapon_energy += this_weapon_energy
	if with_contents:
		for equip in ship_stats['equipment']:
			if equip.hidden:
				continue
			contents += '\n[b]'+equip['name'].capitalize() + \
				':[/b] {ref '+equip['help_page']+'}\n' + \
				make_equipment_bbcode(equip)

	var energy_data: Array = [ s['power'], 
		-max(s['thrust']*s['forward_thrust_energy'],s['reverse_thrust']*s['reverse_thrust_energy'])/1000, \
		-s['turning_thrust']*s['turning_thrust_energy']/1000,
		-weapon_energy,
		-s['heal_shields']*s['shield_repair_energy']-s['heal_armor']*s['armor_repair_energy']- \
			s['heal_structure']*s['structure_repair_energy'],
		0 ]
	energy_data[5] = energy_data[0]+energy_data[1]+energy_data[2]+energy_data[3]+energy_data[4]

	var heat_data: Array = [ -s['cooling'], 
		max(s['thrust']*s['forward_thrust_heat'],s['reverse_thrust']*s['reverse_thrust_heat'])/1000, \
		s['turning_thrust']*s['turning_thrust_heat']/10000,
		weapon_heat,
		s['heal_shields']*s['shield_repair_heat']+s['heal_armor']*s['armor_repair_heat']+ \
			s['heal_structure']*s['structure_repair_heat'],
		0 ]
	heat_data[5] = heat_data[0]+heat_data[1]+heat_data[2]+heat_data[3]+heat_data[4]
	
	var mass = utils.ship_mass(s,false)
	var mass_when_full = utils.ship_mass(s,true)
	var max_thrust = max(max(s['reverse_thrust'],s['thrust']),0)
	var bbcode = '[b]Ship Design:[/b] [i]'+s['display_name']+'[/i]'+annotation+'\n'
	if show_id:
		bbcode += '[b]ID:[/b] [code]'+s['name']+'[/code]\n'
	bbcode += '[b]Hull:[/b] {ref '+s['help_page']+'}\n'

	if heat_data[0]+max(heat_data[1],heat_data[2])>0:
		bbcode += '[error]Ship has insufficient cooling to move![/error]'

	if energy_data[0]+max(energy_data[1],energy_data[2])<0:
		bbcode += '[error]Ship has insufficient power to move![/error]'

	# Main data table:

	bbcode += '[table=5]'

	bbcode += max_and_repair('Shields:',s['max_shields'],s['heal_shields'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Damage:',str(round(dps))+'/s')

	bbcode += max_and_repair('Armor:',s['max_armor'],s['heal_armor'])
	bbcode += '[cell] [/cell]'
	var max_speed = round(10*max_thrust/max(1e-9,s['drag']*mass))/10
	var max_speed_when_full = round(10*max_thrust/max(1e-9,s['drag']*mass_when_full))/10
	bbcode += make_cell('Max Speed: ',str(max_speed)+' ('+str(max_speed_when_full)+' with max cargo)')

	bbcode += max_and_repair('Structure:',s['max_structure'],s['heal_structure'])
	bbcode += '[cell] [/cell]'
	var hyperspace_speed = round(10*max_thrust*(1+s['hyperthrust'])/max(1e-9,s['drag']*mass))/10
	var hyperspace_speed_when_full = round(10*max_thrust*(1+s['hyperthrust'])/max(1e-9,s['drag']*mass_when_full))/10
	bbcode += make_cell('Hyperspace Speed:',str(hyperspace_speed)+' ('+str(hyperspace_speed_when_full)+' with max cargo)')

#	var k = s['max_fuel']*s['fuel_inverse_density']/s['empty_mass']
#	var d = s['max_fuel']*s['fuel_efficiency']/s['empty_mass']
#	var travel_distance = d * 1.0/k * log(1.0/(1.0+k))
	bbcode += max_and_repair('Fuel:',s['max_fuel'],round(s['heal_fuel']*10)/10)
	bbcode += '[cell][/cell]'
	var turn_rpm = round(s['turning_thrust']/max(1e-9,s['turn_drag']*mass)*100)/100
	var turn_rpm_when_full = round(s['turning_thrust']/max(1e-9,s['turn_drag']*mass_when_full)*100)/100
	bbcode += make_cell('Turn RPM:',str(turn_rpm)+' ('+str(turn_rpm_when_full)+' with max cargo)')
#	bbcode += make_cell('Hyper.Travel:',str(round(travel_distance*10)/10)+'pc')

	bbcode += make_cell('Cargo: ',str(round(s.get('cargo_mass',0)))+'/'+str(round(s.get('max_cargo',0))))
	bbcode += '[cell] [/cell]'
	bbcode += '[cell]Death Explosion[/cell][cell][/cell]'

	bbcode += make_cell('Mass:',mass)
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Radius:',s['explosion_radius'])

	bbcode += make_cell('Drag:',s['drag'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Damage:',s['explosion_damage'])

	bbcode += make_cell('Thrust:',s['thrust'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Delay:',str(round(s['explosion_delay']/60.0*10)/10)+'s')

	if s['reverse_thrust']>0:
		bbcode += make_cell('Reverse:',s['reverse_thrust'])
	else:
		bbcode += '[cell][/cell][cell][/cell]'
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Hit Force:',s['explosion_impulse'])
	
	if s['hyperthrust']>0:
		bbcode += make_cell('Hyperspace:','+'+str(round(s['hyperthrust']*1000)/10)+'%')
	else:
		bbcode += '[cell][/cell][cell][/cell]'
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Item Slots:',s['item_slots'])
	
	bbcode += max_and_repair('Energy:',s['battery'],s['power'])
	bbcode += '[cell] [/cell]'
	
	bbcode += max_and_repair('Heat:',s['empty_mass']*s['heat_capacity'],-s['cooling'])
	bbcode += '[cell] [/cell][cell][/cell][cell][/cell]'
	bbcode += '[/table]\n'

	# Heat and energy budget tables:

	bbcode += '\n[b]Budgets[/b]:\n[table=3]'
	bbcode += make_cell3(' ','Energy','Heat')
	var headings: Array = [ 'Idle', 'Thrust', 'Turn', 'Fire', 'Repair', 'Remaining' ]
	for i in range(len(headings)):
		bbcode += make_cell3(headings[i],stepify(energy_data[i],.1),stepify(heat_data[i],.1))
	bbcode += make_cell3('Limit',stepify(s['battery'],.1),stepify(s['empty_mass']*s['heat_capacity'],.1))
	bbcode += '[/table]\n'

	# Resistance and passthru tables:

	var resistance_colors: Array = [ [ -INF, '#ff3333' ], [ -40, '#ff7788' ], [ -10, '#bbbb44' ],
		[ 10, '#777777' ], [ 40, '#7788ff' ], [ INF, '#ffaaff' ] ]
	bbcode += make_resist_table(s,['shield_resist','armor_resist','structure_resist'], \
		['Shld','Armr','Struct'], '\n[b]Resistances:[/b]\n','',resistance_colors,-200,75)

	var passthru_colors: Array = [ [ 0, '#777777' ], [ 15, '#bbbb44' ], [ INF, '#ff7788' ] ]
	bbcode += make_resist_table(s,['shield_passthru','armor_passthru'], \
		['Shld','Armr'], '\n[b]Damage Passthrough:[/b]\n','',passthru_colors,0,100)

	if with_contents:
		bbcode += contents
	return bbcode

func make_add_amount(num: float,round_to: float,what: String,end: String = '\n') -> String:
	var s = '+' if num>0 else '-'
	return s+' '+str(round(num*round_to)/round_to)+' '+what+end

func make_add_percent(num: float,round_to: float,what: String, end: String = '\n') -> String:
	var s = '+' if num>1.0 else ''
	return what+' '+s+str(round(num*round_to*100.0)/round_to)+'%'+end

func make_add_resist(index: int,stat: String,stats: Dictionary,prefix: String,what: String) -> String:
	if stats[stat].size()<=index:
		return ''
	var value: float = stats[stat][index]
	if abs(value)<1e-6:
		return ''
	return prefix + make_add_percent(value,1,DAMAGE_DISPLAY_NAMES[index]+' '+what)

func make_equipment_bbcode(stats) -> String:
	var bbcode: String = 'size '+str(stats['item_size_x'])+'x'+str(stats['item_size_y'])+'\n'
	if stats['mount_type_display']:
		bbcode='type: '+stats['mount_type_display']
	bbcode += 'mass '+str(stats['add_mass'])+' tons\n'

	if stats['add_thrust']>0:
		var eps = stats['forward_thrust_energy']*stats['add_thrust']/1000
		var hps = stats['forward_thrust_heat']*stats['add_thrust']/1000
		bbcode+='+'+str(round(stats['add_thrust']))+' thrust (' + \
			str(round(eps*10)/10)+'energy/s, '+str(round(hps*100)/100)+' heat/s)\n'
	if stats['add_reverse_thrust']>0:
		var eps = stats['reverse_thrust_energy']*stats['add_reverse_thrust']/1000
		var hps = stats['reverse_thrust_heat']*stats['add_reverse_thrust']/1000
		bbcode+='+'+str(round(stats['add_reverse_thrust']))+' reverse thrust (' + \
			str(round(eps*10)/10)+'energy/s, '+str(round(hps*100)/100)+' heat/s)\n'
	if stats['add_turning_thrust']>0:
		var eps = stats['turning_thrust_energy']*stats['add_turning_thrust']/1000
		var hps = stats['turning_thrust_heat']*stats['add_turning_thrust']/1000
		bbcode+='+'+str(round(stats['add_turning_thrust']))+ \
			' turning thrust ('+str(round(eps*10)/10)+'energy/s, '+str(round(hps*100)/100)+' heat/s)\n'

	if stats['add_fuel']>0:
		bbcode+=''+make_add_amount(stats['add_fuel'],10,'fuel')
	if stats['add_heal_fuel']>0:
		bbcode+=''+make_add_amount(stats['add_heal_fuel'],10,'fuel per second')

	if stats['add_drag']>0:
		bbcode += ''+make_add_amount(stats['add_drag'],10,'drag')
	if abs(stats['mult_drag']-1.0)>1e-6:
		bbcode += ''+make_add_percent(stats['mult_drag'],10,'drag')

	if stats['add_turn_drag']>0:
		bbcode += ''+make_add_amount(stats['add_turn_drag'],10,'turn drag')
	if abs(stats['mult_turn_drag']-1.0)>1e-6:
		bbcode += ''+make_add_percent(stats['mult_turn_drag'],10,'turn drag')

	if stats['add_shields']>0:
		bbcode += ''+make_add_amount(stats['add_shields'],10,'shields')
	if stats['add_armor']>0:
		bbcode += ''+make_add_amount(stats['add_armor'],10,'armor')
	if stats['add_structure']>0:
		bbcode += ''+make_add_amount(stats['add_structure'],10,'structure')

	if stats['add_heal_shields']>0:
		bbcode += ''+make_add_amount(stats['add_heal_shields'],10,'shields/sec','') + \
			' ('+str(stepify(stats['add_heal_shields']*stats['shield_repair_energy'],.1))+' energy/s ' + \
			str(stepify(stats['add_heal_shields']*stats['shield_repair_heat'],.01))+' heat/s)\n'
	if stats['add_heal_armor']>0:
		bbcode += ''+make_add_amount(stats['add_heal_armor'],10,'armor/sec','') + \
			' ('+str(stepify(stats['add_heal_armor']*stats['armor_repair_energy'],.1))+' energy/s ' + \
			str(stepify(stats['add_heal_armor']*stats['armor_repair_heat'],.01))+' heat/s)\n'
	if stats['add_heal_structure']>0:
		bbcode += ''+make_add_amount(stats['add_heal_structure'],10,'structure/sec','') + \
			' ('+str(stepify(stats['add_heal_structure']*stats['structure_repair_energy'],.1))+' energy/s ' + \
			str(stepify(stats['add_heal_structure']*stats['structure_repair_heat'],.01))+' heat/s)\n'
	
	if stats['add_explosion_damage']:
		bbcode += ''+make_add_amount(stats['add_explosion_damage'],1,'death explosion damage')
	if stats['add_explosion_radius']:
		bbcode += ''+make_add_amount(stats['add_explosion_radius'],10,'death explosion radius')
	if stats['add_explosion_impulse']:
		bbcode += ''+make_add_amount(stats['add_explosion_impulse'],1,'death explosion impulse')
	if stats['add_explosion_delay']:
		bbcode += ''+make_add_amount(stats['add_explosion_delay'],10,'death explosion delay')

# warning-ignore:narrowing_conversion
	var last_type: int = min(max(stats['add_shield_resist'].size(),max(stats['add_shield_passthru'].size(), \
		max(stats['add_armor_resist'].size(),max(stats['add_armor_passthru'].size(), \
		stats['add_structure_resist'].size())))),DAMAGE_DISPLAY_NAMES.size())
	for i in range(last_type):
		bbcode += make_add_resist(i,'add_shield_resist',stats,'','shield resist')
		bbcode += make_add_resist(i,'add_shield_passthru',stats,'','shield passthrough')
		bbcode += make_add_resist(i,'add_armor_resist',stats,'','armor resistance')
		bbcode += make_add_resist(i,'add_armor_passthru',stats,'','armor passthrough')
		bbcode += make_add_resist(i,'add_structure_resist',stats,'','structure resistance')
	
	if stats['add_heat_capacity']:
		bbcode += ''+make_add_amount(stats['add_heat_capacity'],100,'heat capacity')
	if stats['add_cooling']>0:
		bbcode += '+'+str(round(stats['add_cooling']*1000)/1000)+' cooling\n'
	elif stats['add_cooling']<0:
		bbcode += '+'+str(round(abs(stats['add_cooling']*1000))/1000)+' heat\n'
	if stats['add_battery']:
		bbcode += ''+make_add_amount(stats['add_battery'],1,'energy storage')
	if stats['add_power']:
		bbcode += ''+make_add_amount(stats['add_power'],100,'power')
	return bbcode

func make_table_from_item_lists(items: Dictionary) -> String:
	var cell_sizes = []
	var total_cells = 0
	for list in items:
		cell_sizes.append(len(list))
		total_cells += len(list)
	
	var cells_before = 0
	var last_item_on_left = 0
	for i in range(len(items)):
		var cells_here = len(items[i])
		var cells_after = total_cells - cells_before - cells_here
		cells_before += cells_here
		if cells_after<=cells_before:
			last_item_on_left = i
			break
	if last_item_on_left==1 and len(items)==2:
		last_item_on_left=0
	
	var left_cells = []
	var i = 0
	while i<=last_item_on_left:
		for cell in items[i]:
			left_cells.append(cell)
		i += 1
	var right_cells = []
	while i<len(items):
		for cell in items[i]:
			right_cells.append(cell)
		i += 1
	
	var bbcode = '[table=5]'
	var rows = max(len(left_cells),len(right_cells))
	for row in range(rows):
		if row>=len(left_cells):
			bbcode += '[cell][/cell][cell][/cell]'
		else:
			bbcode += left_cells[row]
		bbcode += '[cell]  [/cell]'
		if row>=len(right_cells):
			bbcode += '[cell][/cell][cell][/cell]'
		else:
			bbcode += right_cells[row]
	bbcode += '[/table]\n'
	return bbcode


func old_make_equipment_bbcode(equipment_stats) -> String:
	var s = equipment_stats
	var items=[ [
		make_cell(s['mount_type_display'].capitalize()+':',
			str(s['item_size_x'])+'x'+str(s['item_size_y'])),
		make_cell('Mass:',plus_minus(s['add_mass'])),
	] ]
	if s['add_shields'] or s['add_heal_shields']:
		items[0].append(add_max_and_repair('Shields:',s['add_shields'],s['add_heal_shields']))
	if s['add_armor'] or s['add_heal_armor']:
		items[0].append(add_max_and_repair('Armor:',s['add_armor'],s['add_heal_armor']))
	items[0].append(add_max_and_repair('Structure:',s['add_structure'],s['add_heal_structure']))

	if s['add_thrust'] or s['add_reverse_thrust'] or s['add_turning_thrust']:
		items.append([
			make_cell('Thrust:',plus_minus(s['add_thrust'])),
			make_cell('Reverse:',plus_minus(s['add_reverse_thrust'])),
			make_cell('Turn:',plus_minus(s['add_reverse_thrust'])),
		])

	if s['add_drag'] or s['add_turn_drag']:
		items.append([
			make_cell('Drag:',plus_minus(s['add_drag'])),
			make_cell('Turn Drag:',plus_minus(s['add_turn_drag'])),
		])
	if s['mult_drag'] or s['mult_turn_drag']:
		items.append([
			make_cell('Drag:','x'+str(s['mult_drag'])),
			make_cell('Turn Drag:','x'+str(s['mult_turn_drag'])),
		])

	if s['add_explosion_damage'] or s['add_explosion_radius'] \
			or s['add_explosion_impulse'] or s['add_explosion_delay']:
		var add_delay = round(s['add_explosion_delay']/60.0*10)/10
		items.append([
			make_cell('Death Explosion',''),
			make_cell('Radius:',plus_minus(s['add_explosion_radius'])),
			make_cell('Damage:',plus_minus(s['add_explosion_damage'])),
			make_cell('Delay:',plus_minus(add_delay)+'s'),
			make_cell('Hit Force:',plus_minus(s['add_explosion_impulse'])),
		])

	return make_table_from_item_lists(items)
