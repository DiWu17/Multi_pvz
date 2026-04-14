extends AttackComponentBulletPultBase
class_name AttackComponentBulletCorn
## 玉米投手攻击行为组件

## 投射黄油的概率
@export_range(0,1,0.01) var p_butter:float = 0.5
## body中的黄油节点
@export var sprite_2d_butter_in_body:Sprite2D


## 随机选择黄油子弹或玉米子弹,攻击动画开始时调用
func random_choose_butter_or_corn():
	## 多人模式：仅 Host 做随机，广播结果给客户端
	if NetworkManager.is_multiplayer:
		if NetworkManager.is_server():
			var is_butter := randf() < p_butter
			_apply_butter_choice(is_butter)
			## 通过植物所在格子的行列标识该玉米投手
			var plant_owner := owner as Plant000Base
			if is_instance_valid(plant_owner):
				NetworkManager.broadcast_corn_butter_choice.rpc(
					plant_owner.row_col.x, plant_owner.row_col.y, is_butter
				)
		# 客户端不做随机，等待 Host 广播
		return

	## 单人模式：原始逻辑
	var p = randf()
	if p < p_butter:
		attack_bullet_type = BulletRegistry.BulletType.Bullet011Butter
		sprite_2d_butter_in_body.visible = true
	else:
		attack_bullet_type = BulletRegistry.BulletType.Bullet010Corn

## 应用黄油/玉米选择
func _apply_butter_choice(is_butter: bool):
	if is_butter:
		attack_bullet_type = BulletRegistry.BulletType.Bullet011Butter
		sprite_2d_butter_in_body.visible = true
	else:
		attack_bullet_type = BulletRegistry.BulletType.Bullet010Corn
		sprite_2d_butter_in_body.visible = false


func _shoot_bullet():
	super()
	sprite_2d_butter_in_body.visible = false
