extends Bullet000ParabolaBase

## 黄油控制时间
@export var butter_time:float = 4.0

## 攻击一次
func attack_once(enemy:Character000Base):
	super(enemy)
	if enemy is Zombie000Base:
		enemy.be_butter(butter_time)
		## 多人模式：Host 广播黄油效果
		if NetworkManager.is_multiplayer and NetworkManager.is_server() and enemy.network_id >= 0:
			NetworkManager.broadcast_zombie_butter.rpc(enemy.network_id, butter_time)
