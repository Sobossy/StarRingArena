extends PanelContainer
const Library = preload("res://scripts/core/character_library.gd")
const Catalog = preload("res://scripts/core/skill_catalog.gd")
const TYPE_NAMES = {"all":"全部事件","damage":"伤害","heal":"治疗","shield":"护盾","status":"状态","skill":"技能","field":"场地","death":"淘汰","system":"对局"}
const PHASE_NAMES = {"normal":"恢复常态","charge":"蓄力","release":"释放技能","guard":"防反","thread_dash":"金线冲刺","dayun_charge":"大运蓄力","dayun_rush":"大运冲撞","time_stop":"时停","acheron_charge":"斩击蓄力","acheron_locked":"斩击锁线","acheron_release":"斩击释放"}
var ui
var store
var page: int = 0
var event_page: int = 0
var record: Dictionary = {}
var filtered_events: Array = []
var status_label: Label
var list_view: VBoxContainer
var list_rows: VBoxContainer
var page_label: Label
var previous: Button
var next: Button
var detail_view: VBoxContainer
var tabs: TabContainer
var detail_heading: Label
var actor_rows: VBoxContainer
var event_text: RichTextLabel
var actor_filter: OptionButton
var type_filter: OptionButton
var event_page_label: Label
var event_previous: Button
var event_next: Button
var delete_button: Button
var clear_button: Button
var retry_button: Button
var confirm: ConfirmationDialog
var pending_delete: String = ""

func build(host,history_store) -> void:
	ui = host
	store = history_store
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_theme_stylebox_override("panel",ui._style(Color("0b1523"),ui.LINE,12,24,20))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",12)
	add_child(column)
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title: Label = ui._label("对局记录",25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	retry_button = ui._button("重试保存",_retry)
	heading.add_child(retry_button)
	delete_button = ui._button("删除本局",func(): _confirm_delete(false))
	heading.add_child(delete_button)
	clear_button = ui._button("清空记录",func(): _confirm_delete(true))
	heading.add_child(clear_button)
	heading.add_child(ui._button("返回",go_back))
	status_label = ui._label("",12,ui.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(status_label)
	list_view = VBoxContainer.new()
	list_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(list_view)
	list_rows = _scroll_column(list_view)
	var nav := HBoxContainer.new()
	list_view.add_child(nav)
	previous = ui._button("上一页",func(): page -= 1; _render_list())
	nav.add_child(previous)
	page_label = ui._label("",13)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(page_label)
	next = ui._button("下一页",func(): page += 1; _render_list())
	nav.add_child(next)
	detail_view = VBoxContainer.new()
	detail_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(detail_view)
	detail_heading = ui._label("",16)
	detail_heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_view.add_child(detail_heading)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_view.add_child(tabs)
	var stats := VBoxContainer.new()
	stats.name = "配置与统计"
	tabs.add_child(stats)
	actor_rows = _scroll_column(stats)
	var events := VBoxContainer.new()
	events.name = "战斗事件"
	tabs.add_child(events)
	var filters := HBoxContainer.new()
	events.add_child(filters)
	actor_filter = OptionButton.new()
	actor_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(actor_filter)
	type_filter = OptionButton.new()
	type_filter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in TYPE_NAMES:
		type_filter.add_item(TYPE_NAMES[key])
		type_filter.set_item_metadata(type_filter.item_count-1,key)
	filters.add_child(type_filter)
	actor_filter.item_selected.connect(func(_i): event_page = 0; _filter_events())
	type_filter.item_selected.connect(func(_i): event_page = 0; _filter_events())
	var event_scroll := ScrollContainer.new()
	event_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	events.add_child(event_scroll)
	event_text = RichTextLabel.new()
	event_text.fit_content = true
	event_text.selection_enabled = true
	event_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_text.add_theme_font_size_override("normal_font_size",14)
	event_scroll.add_child(event_text)
	var event_nav := HBoxContainer.new()
	events.add_child(event_nav)
	event_previous = ui._button("上一页",func(): event_page -= 1; _render_events())
	event_nav.add_child(event_previous)
	event_page_label = ui._label("",13)
	event_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_nav.add_child(event_page_label)
	event_next = ui._button("下一页",func(): event_page += 1; _render_events())
	event_nav.add_child(event_next)
	confirm = ConfirmationDialog.new()
	confirm.confirmed.connect(_delete_confirmed)
	add_child(confirm)
	hide()

func _scroll_column(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12)
	scroll.add_child(column)
	return column

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func open_history() -> void:
	store.reload()
	page = 0
	record = {}
	show()
	_render_list()

func open_record(id: String) -> void:
	var loaded: Dictionary = store.load_record(id)
	if loaded.is_empty():
		status_label.text = "这份记录暂时无法读取，可返回列表删除它，其他记录不受影响。"
		show()
		return
	record = loaded
	event_page = 0
	list_view.hide()
	detail_view.show()
	delete_button.show()
	detail_heading.text = _date(record.ended_at)+"  ·  "+_outcome(store.summarize(record))+"\n%s · %d人 · %.1f秒 · 地图 %d×%d · 种子 %d · %s" % ["组队对战" if record.configuration.mode == "teams" else "个人竞技",record.participants.size(),record.elapsed,record.configuration.width,record.configuration.height,record.configuration.seed,record.game_version]
	detail_heading.text += " · "+("超时结束" if record.result.reason == "timeout" else "淘汰决胜")
	detail_heading.tooltip_text = "开始：%s\n结束：%s" % [_date(record.get("started_at",record.ended_at)),_date(record.ended_at)]
	_clear(actor_rows)
	for slot in record.participants:
		var actor: Dictionary = record.actors[int(slot.slot)]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",ui._style(ui.PANEL,ui.LINE,8,12,12))
		actor_rows.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var image := TextureRect.new()
		image.texture = Library.texture_from_path(str(slot.character.get("normal_image","")))
		if image.texture == null:
			image.texture = load("res://assets/icon.svg")
			image.tooltip_text = "历史形象图片缺失，使用占位图"
		image.custom_minimum_size = Vector2(64,64)
		image.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
		var text: Label = ui._label(_actor_description(slot,actor),14)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.text += "\n"+str(slot.character.get("description",""))
		row.add_child(text)
	actor_filter.clear()
	actor_filter.add_item("所有角色")
	for slot in record.participants:
		actor_filter.add_item("%02d %s" % [int(slot.slot)+1,slot.character.name])
	type_filter.select(0)
	tabs.current_tab = 0
	_filter_events()
	_refresh_status()
	show()

func go_back() -> void:
	if confirm.visible:
		confirm.hide()
	elif not record.is_empty():
		record = {}
		_render_list()
	else:
		hide()
		ui._refresh_history_state()

func _render_list() -> void:
	list_view.show()
	detail_view.hide()
	delete_button.hide()
	_clear(list_rows)
	var total: int = store.summaries.size()
	var pages: int = maxi(1,ceili(total/20.0))
	page = clampi(page,0,pages-1)
	for i in range(page*20,mini(total,page*20+20)):
		var entry: Dictionary = store.summaries[i]
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",ui._style(ui.PANEL,ui.LINE,8,12,12))
		list_rows.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var names: Array[String] = []
		for role in entry.roles:
			names.append(str(role.name))
		var text: Label = ui._label(_date(entry.ended_at)+"  ·  "+_outcome(entry)+"\n"+" / ".join(names)+"\n%s · %d人 · %.1f秒 · 种子 %d" % ["组队对战" if entry.mode == "teams" else "个人竞技",entry.roles.size(),entry.elapsed,entry.seed],14)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		row.add_child(ui._button("详情",open_record.bind(str(entry.id)),true))
		row.add_child(ui._button("删除",_request_single_delete.bind(str(entry.id))))
	if total == 0:
		list_rows.add_child(ui._label("暂无完整对局记录。正常结束一局后会自动保存。",16,ui.MUTED))
	page_label.text = "%d / %d 页 · 共%d局" % [page+1,pages,total]
	previous.disabled = page <= 0
	next.disabled = page >= pages-1
	list_rows.get_parent().set_deferred("scroll_vertical",0)
	_refresh_status()

func _refresh_status() -> void:
	retry_button.visible = not store.pending.is_empty()
	clear_button.disabled = store.summaries.is_empty() and store.pending.is_empty()
	status_label.text = "仅保留正常结束的完整对局 · 包含平局 · 记录保存在本机"
	if not store.pending.is_empty():
		status_label.text = "%d局记录尚未完成保存，可点击“重试保存”。%s" % [store.pending.size(),store.last_error]

func _actor_description(slot: Dictionary,actor: Dictionary) -> String:
	var character: Dictionary = slot.character
	var skills: Array[String] = []
	for skill in character.get("skills",[]):
		var parameters: Array[String] = []
		for key in skill.get("parameters",{}):
			parameters.append("%s=%s" % [skill.get("parameter_names",{}).get(key,Catalog.PARAMETER_NAMES.get(key,"参数")),str(skill.parameters[key])])
		skills.append(str(skill.get("name",Catalog.find(str(skill.get("template_id",""))).get("name","技能")))+" · 蓄力%.2f秒\n" % float(skill.get("charge_time",0))+"，".join(parameters))
	var movement_names: Dictionary = {"bounce":"碰壁反弹","chase":"主动追击","kite":"保持距离","wander":"自由游走"}
	return "%02d %s · %s · %s\n剩余生命 %.0f / %.0f · %s\n造成伤害 %.0f · 承受伤害 %.0f（均含护盾）· 治疗 %.0f\n开局生命 %.0f · 速度 %.0f · 碰撞半径 %.0f\n%s" % [int(slot.slot)+1,character.name,_team(int(slot.team)) if record.configuration.mode == "teams" else "个人竞技",movement_names.get(slot.movement,slot.movement),actor.health,actor.max_health,"存活" if actor.alive else "已淘汰",actor.damage_dealt,actor.damage_taken,actor.healing_done,character.max_health,character.speed,character.radius,"\n".join(skills)]

func _filter_events() -> void:
	if record.is_empty():
		return
	var slot: int = actor_filter.selected-1
	var category: String = str(type_filter.get_item_metadata(type_filter.selected))
	filtered_events = record.events.filter(func(event): return (slot < 0 or int(event.get("source",-1)) == slot or int(event.get("target",event.get("side",-1))) == slot) and (category == "all" or _category(str(event.get("kind",""))) == category))
	_render_events()

func _render_events() -> void:
	var pages: int = maxi(1,ceili(filtered_events.size()/100.0))
	event_page = clampi(event_page,0,pages-1)
	var lines: Array[String] = []
	for i in range(event_page*100,mini(filtered_events.size(),event_page*100+100)):
		var event: Dictionary = filtered_events[i]
		lines.append("%.3fs  #%d  %s" % [event.get("time",0),event.get("sequence",i+1),_describe_event(event)])
	event_text.text = "\n\n".join(lines) if not lines.is_empty() else "没有符合条件的事件。"
	event_page_label.text = "%d / %d 页 · %d条事件" % [event_page+1,pages,filtered_events.size()]
	event_previous.disabled = event_page <= 0
	event_next.disabled = event_page >= pages-1
	event_text.get_parent().set_deferred("scroll_vertical",0)

func _describe_event(event: Dictionary) -> String:
	var source: String = _name(int(event.get("source",-1)))
	var target: String = _name(int(event.get("target",event.get("side",-1))))
	var skill: String = _skill_name(str(event.get("skill_id","")))
	match str(event.get("kind","")):
		"damage": return "%s → %s：伤害 %.1f，护盾吸收 %.1f，剩余生命 %.1f（%s，原始伤害 %.1f）" % [source,target,event.amount,event.get("absorbed",0),event.get("health_after",0),skill,event.get("raw_amount",event.amount)]
		"heal": return "%s：恢复生命 %.1f" % [target,event.amount]
		"shield": return "%s：获得护盾 %.1f，当前护盾 %.1f" % [target,event.amount,event.get("shield",0)]
		"shield_end": return "%s：护盾到期" % target
		"status": return "%s → %s：施加%s，强度%s" % [source,target,_status_name(str(event.id)),str(event.power)]
		"status_end": return "%s：%s结束" % [target,_status_name(str(event.id))]
		"mark": return "%s → %s：泰坦印记%d层，减速%.1f%%" % [source,target,event.stacks,float(event.get("slow",0))*100]
		"skill_phase": return "%s：%s · %s" % [source,skill,PHASE_NAMES.get(event.phase,event.phase)]
		"skill_action": return "%s：%s" % [source,{"dry_fire":"空枪白旗","revolver_shot":"射出实弹","revolver_reload":"重新上膛","guard_start":"进入防反","acheron_slash":"斩断棋盘"}.get(event.action,event.action)]
		"projectile": return "%s：%s投射物生成，伤害%.1f" % [source,skill,event.damage]
		"projectile_hit": return "%s → %s：%s投射物命中" % [source,target,skill]
		"projectile_end": return "%s：投射物%s" % [source,{"hit":"命中后消失","expired":"到期消失","outside":"飞出地图","source_dead":"随施术者淘汰而消失"}.get(event.get("reason",""),"结束")]
		"airborne_start": return "%s → %s：击飞%.1f秒" % [source,target,event.duration]
		"airborne_end": return "%s：落地" % target
		"time_stop_start": return "%s：发动时停%.1f秒" % [source,event.duration]
		"time_stop_end": return "%s：时停结束" % source
		"pickup_spawn": return "场地刷新吐司"
		"pickup_taken": return "%s：拾取吐司" % source
		"shrink": return "灰黯之手缩圈，场地剩余%.0f%%" % (float(event.scale)*100)
		"arena_cut": return "%s：新增永久切面墙" % source
		"death": return "%s：%s" % [target,"迷路判负" if event.get("reason","") == "lost" else "被淘汰"]
		"start": return "对局开始 · 种子%d" % event.seed
		"end": return "对局结束 · "+_outcome(store.summarize(record))
	return "其他对局事件"

static func _category(kind: String) -> String:
	if kind in ["damage","heal","shield","death"]: return kind
	if kind in ["status","status_end","mark","airborne_start","airborne_end","shield_end"]: return "status"
	if kind in ["skill_phase","skill_action","projectile","projectile_hit","projectile_end","time_stop_start","time_stop_end"]: return "skill"
	if kind in ["pickup_spawn","pickup_taken","shrink","arena_cut"]: return "field"
	return "system"

func _name(slot: int) -> String:
	for participant in record.get("participants",[]):
		if int(participant.slot) == slot:
			return "%02d %s" % [slot+1,participant.character.name]
	return "场地"

static func _team(team: int) -> String:
	return ["A","B","C","D"][team]+"队" if team >= 0 and team < 4 else "阵营%d" % (team+1)

static func _status_name(id: String) -> String:
	return {"burn":"灼烧","slow":"减速"}.get(id,id)

func _skill_name(id: String) -> String:
	for slot in record.get("participants",[]):
		for skill in slot.character.get("skills",[]):
			if str(skill.get("template_id","")) == id:
				return str(skill.get("name","技能"))
	return {"mimi_punch":"迷迷拳击","titan_execution":"泰坦终结","burn":"灼烧","feiying_landing":"摔落伤害","aglaea_threads_contact":"阿格莱雅碰撞","aglaea_threads_thread":"金线伤害","aglaea_threads_dash":"沿金线冲刺"}.get(id,"攻击")

static func _outcome(entry: Dictionary) -> String:
	if entry.result.get("draw",false):
		return "平局"
	var team: int = int(entry.result.winning_team)
	if entry.mode == "teams":
		return _team(team)+"获胜"
	for role in entry.roles:
		if int(role.team) == team:
			return "%02d %s获胜" % [int(role.slot)+1,role.name]
	return "对局已完成"

static func _date(timestamp: float) -> String:
	var zone: Dictionary = Time.get_time_zone_from_system()
	return Time.get_datetime_string_from_unix_time(int(timestamp)+int(zone.bias)*60,true).replace("-","/")

func _confirm_delete(all_records: bool) -> void:
	pending_delete = "all" if all_records else str(record.get("id",""))
	_show_delete_dialog(all_records)

func _request_single_delete(id: String) -> void:
	pending_delete = id
	_show_delete_dialog(false)

func _show_delete_dialog(all_records: bool) -> void:
	confirm.title = "清空对局记录" if all_records else "删除本局记录"
	confirm.dialog_text = "将删除本机全部已保存记录，此操作不能撤销。" if all_records else "将删除这局的战报与全部事件，此操作不能撤销。"
	confirm.ok_button_text = "确认清空" if all_records else "确认删除"
	confirm.popup_centered()

func _delete_confirmed() -> void:
	var success: bool = store.clear_records() if pending_delete == "all" else store.delete_record(pending_delete)
	if success:
		record = {}
		_render_list()
	else:
		status_label.text = store.last_error
	ui._refresh_history_state()

func _retry() -> void:
	store.retry_pending()
	if record.is_empty():
		_render_list()
	else:
		open_record(str(record.id))
	ui._refresh_history_state()
