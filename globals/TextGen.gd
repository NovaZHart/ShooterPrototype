extends Node

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

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,str(maxval)+' (+'+str(repairval)+'/s)')
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
			dps += weapon['damage'] / max(1.0/60,weapon['firing_delay'])*n
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
		if stats['damage']:
			if stats['firing_delay']<=1.0/60:
				bbcode += make_cell('shots per second','60 (continuous fire)')
			else:
				bbcode += make_cell('shots per second',ceil(1.0/max(1.0/60,stats['firing_delay'])))
			bbcode += make_cell('damage per shot',stats['damage'])
			bbcode += make_cell('damage per second',round(stats['damage']/max(1.0/60,stats['firing_delay'])*10)/10)
		if stats['impulse']:
			bbcode += make_cell('hit force per second',round(stats['impulse']/max(1.0/60,stats['firing_delay'])*10)/10)
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


func make_ship_bbcode(ship_stats,with_contents=true,annotation='',show_id=null) -> String:
	var contents: String = '' #'[b]Contents:[/b]\n'
	if show_id==null:
		show_id = game_state.game_editor_mode
	var dps: float = 0
	for weapon in ship_stats['weapons']:
		if with_contents:
			contents += '\n[b]'+weapon['name'].capitalize() + \
				':[/b] {ref '+weapon['help_page']+'}\n' + \
				make_weapon_bbcode(weapon)
		dps += weapon['damage'] / max(1.0/60,weapon['firing_delay'])
	
	if with_contents:
		for equip in ship_stats['equipment']:
			contents += '\n[b]'+equip['name'].capitalize() + \
				':[/b] {ref '+equip['help_page']+'}\n' + \
				make_equipment_bbcode(equip)
	
	if not contents:
		contents='\n'
	
	var s = ship_stats
	var mass = utils.ship_mass(s)
	var max_thrust = max(max(s['reverse_thrust'],s['thrust']),0)
	var bbcode = '[b]Ship Design:[/b] [i]'+s['display_name']+'[/i]'+annotation+'\n'
	if show_id:
		bbcode += '[b]ID:[/b] [code]'+s['name']+'[/code]\n'
	bbcode += '[b]Hull:[/b] {ref '+s['help_page']+'}\n[table=5]'

	bbcode += max_and_repair('Shields:',s['max_shields'],s['heal_shields'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Damage:',str(round(dps))+'/s')

	bbcode += max_and_repair('Armor:',s['max_armor'],s['heal_armor'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Max Speed:',round(max_thrust/max(1e-9,s['drag']*mass)))

	bbcode += max_and_repair('Structure:',s['max_structure'],s['heal_structure'])
	bbcode += '[cell] [/cell]'
	bbcode += make_cell('Turn RPM:',round(s['turning_thrust']/max(1e-9,s['turn_drag']*mass)*100)/100)

	var k = s['max_fuel']*s['fuel_inverse_density']/s['empty_mass']
	var d = s['max_fuel']*s['fuel_efficiency']/s['empty_mass']
	var travel_distance = d * 1.0/k * log(1.0/(1.0+k))
	bbcode += max_and_repair('Fuel:',s['max_fuel'],s['heal_fuel'])
	bbcode += '[cell][/cell]'
	bbcode += make_cell('Hyper.Travel:',str(round(travel_distance*10)/10)+'pc')

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
	
	bbcode += '[/table]\n'

	if contents:
		bbcode += contents
	return bbcode

func make_equipment_bbcode(equipment_stats):
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
