import Foundation

public enum FieldManual {
    public struct Section: Identifiable {
        public var id: String { title }
        public var title: String
        public var body: String
    }

    public static let guide: [Section] = [
        Section(
            title: "Stop, breathe, inventory",
            body: "If you are not in immediate danger, sit. Count people. Count injuries. Count daylight. Name what you have in pockets and pack out loud. Panic burns calories and judgment. Blackout stays on this device; it will not fetch a rescue plan."
        ),
        Section(
            title: "Shelter before cleverness",
            body: "Wind and wet kill faster than hunger. Get out of moving air. Use the lee of a ridge, dense spruce, a boulder, or a trench in snow. Insulation under you matters as much as over you. Dead air in clothing is heat. Cotton that is wet is a liability; dry it against your core if you must keep it."
        ),
        Section(
            title: "Water in the Front Range",
            body: "Treat every untreated source as unsafe. Snow is not a shortcut if you eat it cold — melt it. Prefer moving water over stagnant. If you have a stove, bring to a rolling boil. If you have no treatment, ration sweat first: shade, slow movement, mouth closed. This guide will not mark water as drinkable."
        ),
        Section(
            title: "Fire that earns its fuel",
            body: "A fire is signaling, drying, and morale. It is also a wildfire start. Clear to mineral soil. Keep it small. Tinder: inner bark, fatwood, dry grass under the second layer of forest litter. Kindling no thicker than a pencil. Feather sticks beat wet matches. Never leave it. Drown, stir, drown."
        ),
        Section(
            title: "Signaling",
            body: "Three of anything is a distress pattern: three blasts, three fires, three flashes. Contrast against snow or rock. A mirror works on any bright sky, even without a direct sun disk. Save battery for night signaling and for SOS in Blackout. Do not assume a mesh peer can hear you this pass."
        ),
        Section(
            title: "Weather on the Front Range",
            body: "Afternoon storms stack on the Divide and walk east. If the wind flips and the temperature drops fast, get off exposed rock. Lightning takes high points and lone trees. Hypothermia starts with stumbling and quiet. Rewarm the torso before the limbs. Do not chase a summit timeline."
        ),
        Section(
            title: "Navigation without a live map",
            body: "The bundled pack is a Denver-adjacent sample, not a world map. Trust a compass heading and last-known more than a blank guess. Ridgelines run north-south along much of this sample. Drainages go to people eventually, but they also go to cliffs. If you have no fix, stay put once you have shelter."
        ),
        Section(
            title: "Injuries you can slow",
            body: "Direct pressure on bleeding. Splint how it lies if moving the limb causes a scream. Cool a burn with clean water, then cover. Do not pack wounds with wild plants. Field Vision will not diagnose. Unknown is the honest state when you do not know."
        )
    ]

    public static let skills: [Section] = [
        Section(
            title: "Debris hut",
            body: "Ridge pole from a downed limb, wrist-thick, longer than you. Ribs at 45 degrees. Pile leaves, needles, or grass until the walls are as thick as your arm is long. Crawl in feet first. Leave a plug of debris for the door. If you can see light through the walls, it is not finished."
        ),
        Section(
            title: "Bow drill, then the easier fire",
            body: "Bow drill is a skill to practice at home. In the field, a ferro rod and fatwood beat pride. If you must: dry spindle, dry board, a notch that captures powder, a bow with slack enough to bite. Ember goes to a tinder bundle you have already shredded to hair. Blow from the side, not the top."
        ),
        Section(
            title: "Cordage",
            body: "Inner bark of deadfall, yucca-style leaves where they exist, or clothing strips. Reverse wrap: twist away, wrap toward. Two-ply is enough for a ridge line if you do not shock-load it. Shoelaces are already cordage. Do not cut your only pair until you have a plan to replace them."
        ),
        Section(
            title: "Snow trench",
            body: "In deep snow, a trench with a roof of skis, branches, and a tarp beats an open bivy. Keep the sleeping surface above the cold well. Vent. Mark the roof so nobody walks through you. This is Front Range winter logic, not a desert skill."
        ),
        Section(
            title: "Deadfall awareness",
            body: "Widowmakers hang in beetle-kill pine. Look up before you look down. Do not camp under leaning trunks. At night, a creek sounds like a highway; walk it in daylight first. Talus shifts. Test each block with a quiet foot."
        ),
        Section(
            title: "Leave-no-trace under stress",
            body: "Survival is not a license to wreck a drainage. Cat-hole 6–8 inches, 200 feet from water if you can. Pack out tape and wrappers. Kill the fire until it is cold in your hand. The next party may be the one that finds you."
        ),
        Section(
            title: "What this app will not do",
            body: "Blackout will not tell you a plant is food. It will not auto-dial 911. It will not download a better map in the field. Primitive skills are slower than a charged phone and a known walkout. Use both."
        )
    ]
}
