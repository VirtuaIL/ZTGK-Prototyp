tool
extends SceneTree

func _init():
    var a = CSGCylinder3D.new()
    print("Properties: ")
    for p in a.get_property_list():
        print(p.name)
    quit()