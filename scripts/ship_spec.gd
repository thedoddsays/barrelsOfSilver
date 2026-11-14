extends Resource
class_name ShipSpec
## One ship type from docs/ship-roster.md: size, handling, guns and rig. A Ship builds its
## hull, physics and placeholder visuals from this. Data lives in data/ships/*.tres.
##
## Scale notes: lengths are real metres (our ships are built at real size; only *speed* is
## arcade "game scale"). Mass is game-scale tonnes: the 16 m sloop is the 20 t baseline that
## all handling was tuned on, and other ships' forces scale from it automatically.

enum Rig { FORE_AND_AFT, MIXED, SQUARE, OARED }

@export var id := "sloop"
@export var display_name := "Sloop"
@export_enum("light", "medium", "heavy", "line", "merchant") var tier := "light"
@export_enum("common", "uncommon", "rare", "very rare", "legendary") var rarity := "common"

@export_group("Hull")
@export var length := 16.0  ## overall hull length, metres
@export var beam := 4.6  ## width, metres
@export var hull_height := 2.2  ## keel to deck at the waist, metres
@export var mass_t := 20.0  ## game-scale tonnes (sloop = 20)
@export var max_hull := 100.0
@export_enum("very shallow", "shallow", "medium", "deep", "very deep") var draft := "shallow"

@export_group("Handling")
@export var rig := Rig.FORE_AND_AFT  ## which point-of-sail curve (see Ship.RIG_CURVES)
@export var speed_mult := 1.0  ## top speed relative to the sloop (about 12 m/s)
@export var turn_mult := 1.0  ## turning relative to the sloop

@export_group("Crew and guns")
@export var max_crew := 80.0
@export var guns_per_side := 5
@export var gun_decks := 1  ## rows of gun ports; guns are split evenly between them
@export var cargo_t := 40.0

@export_group("Rig visuals")
## Optional 3D model (.glb from tools/blender). It carries the hull, masts and standing
## rigging plus marker nodes (mast_N, mast_N_head, jib_tack, jib_head, flag, gun_N) that
## Ship hangs the animated sails on. Without one, Ship builds placeholder geometry.
@export var model: PackedScene
## One entry per mast, bow to stern: "square" (yards and square sails), "gaff" (a
## fore-and-aft sail on a boom that swings to leeward) or "spanker" (a full-rigged ship's
## mizzen: a gaff sail with a square topsail above it).
@export var masts: PackedStringArray = PackedStringArray(["gaff"])
@export var mast_height_frac := 0.8  ## tallest mast height as a fraction of length
@export var jib := true  ## triangular headsail from the foremast to the bowsprit
