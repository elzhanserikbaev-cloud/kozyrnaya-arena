extends Node
## Узел для сетевых тестов: RPC ping/pong. Должен лежать по одинаковому пути у всех участников.

signal got_ping(from_id: int)
signal got_pong(rtt_msec: int, host_id: int)


@rpc("any_peer", "call_remote", "reliable")
func ping(t: int) -> void:
	var from := multiplayer.get_remote_sender_id()
	got_ping.emit(from)
	pong.rpc_id(from, t, multiplayer.get_unique_id())


@rpc("authority", "call_remote", "reliable")
func pong(t: int, host_id: int) -> void:
	got_pong.emit(Time.get_ticks_msec() - t, host_id)
