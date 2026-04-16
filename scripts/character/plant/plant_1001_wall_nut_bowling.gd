extends Plant000Base
class_name Plant1001WallNutBowling

@export var bowling_bullet_scene:PackedScene
var bullets:Node2D

## 初始化正常出战角色
func ready_norm():
	super()
	## 保龄球坚果两端独立在 ready_norm 中死亡，跳过 Host 广播，
	## 防止客户端在 await 期间被 broadcast_plant_death 提前杀死导致子弹不生成
	skip_death_broadcast = true
	bullets = Global.main_game.bullets
	await get_tree().physics_frame
	_launch_bowling()
	character_death_disappear()


func _launch_bowling():
	## 发射保龄球子弹
	var bullet:Bullet000Base = bowling_bullet_scene.instantiate()
	var bullet_paras = {
			Bullet000NormBase.E_InitParasAttr.BulletLane : lane,
			Bullet000NormBase.E_InitParasAttr.Position : bullets.to_local(global_position),
		}
	bullet.init_bullet(bullet_paras)
	bullets.add_child(bullet)
