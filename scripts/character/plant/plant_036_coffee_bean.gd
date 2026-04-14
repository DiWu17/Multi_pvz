extends Plant000Base
class_name Plant036CoffeeBean

## 唤醒植物
func awake_up_plant():
	plant_cell.coffee_bean_awake_up()
	## 多人模式：Host 广播唤醒效果给客户端
	if NetworkManager.is_multiplayer and NetworkManager.is_server():
		NetworkManager.broadcast_coffee_bean_awake.rpc(
			plant_cell.row_col.x,
			plant_cell.row_col.y
		)
