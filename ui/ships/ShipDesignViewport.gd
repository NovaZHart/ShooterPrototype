extends Node

func instance_scene(scene: PackedScene) -> Node:
	return scene.instance()

func assemble_ship(node: simple_tree.SimpleNode) -> RigidBody:
	return node.assemble_ship()
