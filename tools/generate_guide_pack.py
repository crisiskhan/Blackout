#!/usr/bin/env python3
"""Write Blackout/GuidePack: real field articles + inverted index. No network."""
from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACK = ROOT / "Blackout" / "GuidePack"

STOP = {
    "the", "a", "an", "of", "to", "and", "in", "on", "for", "with", "from", "is", "are",
    "be", "or", "as", "at", "by", "it", "if", "not", "this", "that", "you", "your",
    "into", "than", "then", "but", "can", "will", "do", "does", "was", "were",
}

ARTICLES = [
    ("water-treat-source", "water", ["boil", "filter", "giardia"],
     "Treat every untreated source",
     "Treat every untreated Front Range creek as unsafe. Boil one minute at a rolling boil; add a minute above about 2000 m. A filter rated for protozoa is not a virus filter. Chemical drops need contact time written on the bottle — cold water is slower. Do not mark water drinkable because it looks clear. Ration sweat first: shade, slow travel, mouth closed. This is not a potability certificate."),
    ("water-melt-snow", "water", ["snow", "melt", "stove"],
     "Melt snow, do not eat it cold",
     "Eating cold snow drops core temperature and costs more water than it returns. Melt it in a pot, even a metal cup over a tiny stove. Add a splash of liquid water first so the snow does not scorch. Yellow or pink snow is not a shortcut. Pack a lid. Steam is lost water. If you have no stove, a dark bottle in sun still melts slower than a fire. Keep melt away from fuel taste."),
    ("water-find-in-dry", "water", ["drainage", "dew", "seep"],
     "Find water without a map pin",
     "Drainages collect. Follow game trails downhill in the morning. Seeps show as greener grass on a dry slope. Dew on a tarp before sunrise is a trickle, not a plan. Avoid stagnant cattle ponds when a moving trickle exists. Do not descend a canyon you cannot climb in fading light just because you hear water. Stay put once you have a treated litre and shelter."),
    ("water-ration", "water", ["ration", "sweat", "shade"],
     "Ration sweat, not just sips",
     "The first water economy is sweat. Rest in shade during the hot hours. Loosen the pace. Cover skin. Breathe through the nose. Sipping is fine; gasping after a sprint is not. Dark urine is a late sign. Do not take salt tablets without water. Party of one: tell someone your drainage plan before you move. Blackout will not fetch a spring."),
    ("fire-site", "fire", ["mineral", "clear", "wildfire"],
     "Fire that does not become a wildfire",
     "Clear to mineral soil. Scrape duff until you see dirt or rock. Keep the fire small — a cook fire, not a bonfire. Sit upwind of sparks. A ring of rocks does not make a safe fire on duff. Drown, stir, drown until it is cold in your hand. Never leave it. Front Range wind shifts in the afternoon. If restrictions are unknown, assume fire is a last-resort signal, not comfort."),
    ("fire-tinder", "fire", ["tinder", "fatwood", "feather"],
     "Tinder that actually takes a spark",
     "Inner bark of deadfall, fatwood from pine stumps, and dry grass under the second litter layer beat wet surface stuff. Feather a stick until the curls are hair-thin. Cotton balls and petroleum from a kit are honest. Wet matches are a lesson. Build a tinder bundle first, then the spark. Blow from the side. An ember in a fist-sized bundle becomes flame. Pride is not tinder."),
    ("fire-bow-drill", "fire", ["bow", "spindle", "ember"],
     "Bow drill is practice, ferro is field",
     "Bow drill belongs in the yard at home. In weather, a ferro rod and fatwood beat pride. If you must: dry spindle, dry board, a notch that captures powder, a bow with just enough slack to bite. Ember goes to a bundle you already shredded. Do not drill on snow. This skill fails in wet beetle-kill faster than people admit. Carry the rod."),
    ("fire-signal", "fire", ["three", "smoke", "night"],
     "Three fires is a distress pattern",
     "Three of anything is a distress pattern: three fires, three blasts, three flashes. Space them so they read as a set from a ridge. Day smoke wants wet greens on a hot coal bed once you have a fire you control. Night wants flame contrast. Do not start three wildfires. One well-placed signal fire plus a mirror is often enough. Save phone battery for night and for SOS in Blackout."),
    ("shelter-lee", "shelter", ["wind", "wet", "insulation"],
     "Shelter before cleverness",
     "Wind and wet kill faster than hunger. Get out of moving air. Use the lee of a ridge, dense spruce, a boulder, or a trench in snow. Insulation under you matters as much as over you. Dead air in clothing is heat. Wet cotton is a liability; dry it against your core if you must keep it. Do not camp in a drainage that can flash. Look up for widowmakers before you look down."),
    ("shelter-debris-hut", "shelter", ["debris", "ridgepole", "leaves"],
     "Debris hut",
     "Ridge pole from a downed limb, wrist-thick, longer than you. Ribs at about 45 degrees. Pile leaves, needles, or grass until the walls are as thick as your arm is long. Crawl in feet first. Leave a plug of debris for the door. If you can see light through the walls, it is not finished. Site it on high enough ground that melt does not fill it. Mark it so nobody walks through the roof."),
    ("shelter-snow-trench", "shelter", ["snow", "trench", "vent"],
     "Snow trench",
     "In deep snow a trench with a roof of skis, branches, and a tarp beats an open bivy. Keep the sleeping surface above the cold well. Vent or you will ice the inside with breath. Mark the roof. A snow cave needs a probe and a lot of time — do not start one at dusk unless you already know the slab. This is Front Range winter logic, not a desert skill."),
    ("shelter-tarp", "shelter", ["tarp", "ridge", "stake"],
     "Tarp that sheds wind",
     "A ridge line and a steep pitch shed wind better than a flat rainfly. Stake into soil or bury deadman sticks in snow. Leave a low side into the weather. Do not build a sail. A space blanket is a vapor barrier, not a tent — combine it with a pit and debris. Party of one: a tarp plus a debris wall is faster than a perfect hut after dark."),
    ("aid-bleeding", "first-aid", ["pressure", "bleed", "wound"],
     "Direct pressure on bleeding",
     "This is first aid, not medical advice. Direct pressure on bleeding with the cleanest cloth you have. Do not pack wounds with wild plants. A tourniquet is a last resort on a limb you are trained to use one on. Keep the person warm. Elevate only if it does not increase pain. Field Vision will not diagnose. Unknown is honest when you do not know. Get to real care when you can."),
    ("aid-fracture", "first-aid", ["splint", "limb", "move"],
     "Splint how it lies",
     "This is first aid, not medical advice. If moving a limb causes a scream, splint how it lies with padding and a rigid stay — trekking pole, stay from a pack, thick bark. Check fingers or toes for color after. Do not straighten a deformity because it looks wrong. Evacuate is the plan. Pain plus numbness plus cold digits is a reason to stop tightening."),
    ("aid-hypothermia", "first-aid", ["hypothermia", "rewarm", "stumble"],
     "Rewarm the torso first",
     "This is first aid, not medical advice. Hypothermia starts with stumbling, mumbling, and a quiet person. Get them out of wind. Swap wet layers. Rewarm the torso before the limbs. Sweet warm drink if they can swallow on their own. Do not rub cold limbs hard. Do not put a severely cold person in a hot bath. You are not a clinic. Seek real care."),
    ("aid-burn", "first-aid", ["burn", "cool", "cover"],
     "Cool a burn, then cover",
     "This is first aid, not medical advice. Cool a burn with clean water, then cover loosely. Do not pack with butter, mud, or plant pulp. Blisters: leave intact if you can. Smoke in a valley is also a lung problem — move to cleaner air. Blackout will not dose pain medicine. Unknown remains valid."),
    ("signal-three", "signaling", ["three", "mirror", "contrast"],
     "Three of anything",
     "Three of anything is a distress pattern. A mirror works on any bright sky, even without a crisp sun disk — flash the horizon in a slow sweep. Contrast against snow or rock. Ground-to-air: make a shape that is not natural. Save battery for night signaling and for SOS. Do not assume a mesh peer can hear you this pass. Zero nearby is a valid field state."),
    ("signal-night", "signaling", ["strobe", "headlamp", "night"],
     "Night contrast",
     "At night a strobe or a headlamp in a three-flash pattern reads farther than a shout. Shield it from ruining your night vision between flashes. A fire is visible and also a wildfire. A phone screen is a weak strobe — use SOS in Blackout for the logged event, then the OS Emergency SOS gesture if you mean a call. Blackout never auto-dials 911."),
    ("signal-whistle", "signaling", ["whistle", "voice", "three"],
     "Whistle before voice",
     "A whistle outlasts a throat. Three blasts, wait, three blasts. In wind, face the likely trail. Do not wander while blowing. If you have no whistle, a metal cup and a stick is a poor cousin. Party of one: a whistle on the zipper is worth more than a clever blog trick."),
    ("signal-ground", "signaling", ["panel", "trampled", "air"],
     "Ground-to-air that reads",
     "Trample a large V or X in snow. Lay a brightly colored tarp. Put it on a ridge, not in timber. Pilots see edges and contrast. Do not write a novel in pinecones. If you move, leave an arrow of stones showing the direction. This pack will not summon an aircraft."),
    ("nav-compass", "navigation", ["compass", "heading", "ridgeline"],
     "Compass heading over a blank guess",
     "The bundled pack is a Denver-adjacent sample, not a world map. Trust a compass heading and last-known more than a blank guess. Ridgelines run roughly north-south along much of this sample. If GPS is denied, Blackout can dead-reckon from a last-known or a manual pin using heading and steps. That is an estimate, not a survey. When lost with shelter, stay put."),
    ("nav-drainage", "navigation", ["drainage", "people", "cliff"],
     "Drainages go to people and to cliffs",
     "Water goes downhill. People often live on water. Canyons also cliff out. Do not commit to a drainage you cannot see through. A contouring traverse to a known road is often safer than a slot. Manual pin plus compass is a plan. A spinning map with no pack under it is not. Stay on the file tiles you have."),
    ("nav-night-stop", "navigation", ["night", "stop", "terrain"],
     "Stop moving when you cannot read terrain",
     "Night plus unknown slope is how ankles and cliffs happen. If you lose the tread, stop, sit, and wait for light unless remaining is more dangerous than moving. Use a headlamp on the ground, not the horizon. Dead reckoning still accumulates error. Mark your stop with a pin. Party of one: tell the morning plan out loud."),
    ("nav-handrail", "navigation", ["handrail", "bearing", "catching"],
     "Handrail and catching feature",
     "Pick a linear feature you cannot miss: a creek, a road, a power line, a sharp ridge. Aim off so you know which way to turn when you hit it. A catching feature behind the target keeps you from walking forever. Write the bearing on paper. Blackout coarse Navigate is bearing and range, not turn-by-turn."),
    ("weather-afternoon", "weather", ["storm", "divide", "lightning"],
     "Afternoon storms on the Front Range",
     "Afternoon storms stack on the Divide and walk east. If the wind flips and the temperature drops fast, get off exposed rock. Lightning takes high points and lone trees. Crouch on insulating stuff if caught, not under the tallest snag. Hypothermia after a soaking is the second punch. Do not chase a summit timeline into black cloud."),
    ("weather-wind", "weather", ["windchill", "layer", "ridge"],
     "Wind on a ridge is a different climate",
     "Twenty steps off a ridge can be a different season. Add a wind layer before you need it. Wet plus wind is the emergency. A space blanket as a kitesail will fail — use it in a pit. Extreme Saver still leaves coarse Navigate and SOS. Do not wait for a forecast download. There is no URLSession here."),
    ("weather-snow", "weather", ["slab", "avalanche", "terrain"],
     "Snow slope is terrain, not a vibe",
     "This app is not an avalanche forecast. Steep open snow, recent wind loading, and a whoomph are reasons to get off that slope. Travel one at a time on suspect terrain if you must. A sample DEM slope tint is coarse, not a slope-angle class. If you do not know, you do not go. Unknown is valid."),
    ("weather-heat", "weather", ["heat", "siesta", "electrolyte"],
     "Heat on the plains approach",
     "East of the foothills, heat is the problem. Travel early. Siesta. Cover head and neck. Water plus shade beats a noon march. Cramps and confusion are stop signs. This is not a sports-drink prescription. Get out of the sun before you perform."),
    ("plants-unknown", "food-plants", ["unknown", "traits", "never-edible"],
     "Traits only. Never an edible verdict",
     "Blackout will not tell you a plant is food. Field Vision will not either. Record traits: leaf arrangement, sap color, smell, habitat, season. Unknown is the result. Many Front Range look-alikes punish guessing. Hunger is slower than a toxin. Do not eat it because an article listed a family. This card is not an ID."),
    ("plants-berries", "food-plants", ["berry", "unknown", "lookalike"],
     "Berries are not a yes",
     "Color is not safety. White and yellow berries are often a hard no in folklore, and even that rule fails. You still do not get an edible verdict here. Note cluster shape, cane thorns, leaf margin, and habitat. If you cannot name it with certainty you already had, leave it. Unknown."),
    ("plants-mushrooms", "food-plants", ["mushroom", "unknown", "spore"],
     "Mushrooms: Unknown",
     "Do not eat wild mushrooms on a Blackout ID. Cap, gills, ring, volva, spore print, and still Unknown. Fatal look-alikes exist in the Rockies. This article will not name a species as food. If you are starving, mushrooms are the wrong gamble. Seek a known calorie in your pack."),
    ("plants-cattail", "food-plants", ["cattail", "wetland", "traits"],
     "Cattail traits, still not a meal ticket",
     "Cattail is often taught as a wetland plant with strap leaves and a brown spike. That is a trait description, not permission to eat. Wetland plants concentrate whatever is in the water. Unknown remains the field result unless you already knew the plant and the water. Do not forage next to a highway ditch because a card mentioned cattail."),
    ("animals-moose", "animals", ["moose", "space", "calf"],
     "Give moose space",
     "Moose hold ground. If ears pin or the animal walks toward you, put a tree between you and back away. Dogs escalate moose. Calves mean the cow is less patient. Do not run at them for a photo. This is not a behavior PhD. Distance is the skill."),
    ("animals-bear", "animals", ["bear", "food", "noise"],
     "Bear country habits",
     "Make noise on thick trails. Cook and sleep apart if you can. Hang or canister food. A surprised bear wants an exit. Do not stand over a carcass. If you see a cub, you are too close to the sow. Carry whatever deterrent you already own and know how to use. This app will not spray for you."),
    ("animals-cat", "animals", ["lion", "cat", "group"],
     "Mountain lion: look large, do not run",
     "If a lion is staring at close range, look large, pick up kids, do not run, do not crouch like prey. Back away. A stick is a better idea than a sprint. Night travel on a game trail is their time. Party of one: a headlamp and noise help. This is field caution, not a guarantee."),
    ("animals-ticks", "animals", ["tick", "check", "tuck"],
     "Ticks after brush",
     "Tuck pants. Check warm spots after sage and grass. Remove with steady pull on the head, not a twist-and-burn folk trick. A rash or fever later is a clinic problem. This is not a diagnosis. Do not put a tick in a plant poultice."),
    ("tools-knife", "tools", ["knife", "baton", "cut"],
     "Knife that stays a knife",
     "Cut away from your femoral artery. Batoning a cheap folder is how it dies. A fixed blade and a baton split kindling without wrecking the edge on dirt. Keep it dry. A dull knife is the dangerous one. Cordage and tape live with the knife, not in a different zip pocket you will not find at night."),
    ("tools-cordage", "tools", ["cord", "wrap", "shoelace"],
     "Cordage",
     "Inner bark of deadfall, clothing strips, reverse wrap: twist away, wrap toward. Two-ply is enough for a ridge line if you do not shock-load it. Shoelaces are already cordage. Do not cut your only pair until you have a plan to replace them. Bank line in the lid of the pack is a better story."),
    ("tools-ferro", "tools", ["ferro", "striker", "spark"],
     "Ferro rod that throws",
     "Scrape off the coating on a new rod. Use the back of a knife or a dedicated striker, not your only cutting edge into dirt. Sparks go into the bundle, not onto wet duff. Practice at home so the motion is boring. A rod in a fire kit you never opened is jewelry."),
    ("tools-pot", "tools", ["pot", "lid", "stove"],
     "A pot is water, food, and signal",
     "A lid saves fuel. A metal pot is a snow melter and a weak signal mirror. Soot the bottom for better heat if you must, then you own the soot in the pack. Do not melt snow in a coated nonstick you will ruin. Hang it; mice chew bags, not titanium as fast."),
    ("bush-inventory", "bushcraft", ["stop", "inventory", "daylight"],
     "Stop, breathe, inventory",
     "If you are not in immediate danger, sit. Count people. Count injuries. Count daylight. Name what you have in pockets and pack out loud. Panic burns calories and judgment. Blackout stays on this device; it will not fetch a rescue plan. Party size 1 is still a party of one — say the plan twice."),
    ("bush-leave-no-trace", "bushcraft", ["cathole", "fire", "packout"],
     "Leave-no-trace under stress",
     "Survival is not a license to wreck a drainage. Cat-hole about 15–20 cm, far from water if you can. Pack out tape and wrappers. Kill the fire until it is cold in your hand. The next party may be the one that finds you. Do not cut live green for a debris hut if deadfall exists."),
    ("bush-deadfall", "bushcraft", ["widowmaker", "leaner", "camp"],
     "Look up before you look down",
     "Widowmakers hang in beetle-kill pine. Do not camp under leaning trunks. At night a creek sounds like a highway; walk it in daylight first. Talus shifts. Test each block with a quiet foot. A beautiful grove can be a deadfall gallery after wind."),
    ("bush-night-bivy", "bushcraft", ["bivy", "pad", "ground"],
     "Ground insulation beats a clever roof",
     "A thin pad or a pile of boughs under you is the difference between a shiver night and sleep. Roof without floor is a mistake. Sit on the pad while you build. Extreme Saver still shows SOS. Do not spend the last light on Instagram-grade lashings."),
]


def tokenize(text: str) -> list[str]:
    words = re.findall(r"[a-z0-9]+", text.lower())
    return [w for w in words if w not in STOP and len(w) > 1]


def main() -> None:
    PACK.mkdir(parents=True, exist_ok=True)
    records = []
    index: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    for aid, topic, tags, title, body in ARTICLES:
        rec = {
            "id": aid,
            "title": title,
            "topic": topic,
            "tags": tags,
            "body": body,
        }
        records.append(rec)
        bag = tokenize(title + " " + body + " " + " ".join(tags) + " " + topic)
        for w in bag:
            index[w][aid] += 1

    jsonl = PACK / "articles.jsonl"
    jsonl.write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in records))
    (PACK / "inverted.json").write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    manifest = {
        "schema": 1,
        "name": "Blackout GuidePack",
        "kind": "on-device-field-guide",
        "articleCount": len(records),
        "topics": sorted({r["topic"] for r in records}),
        "disclaimer": (
            "On-device field articles. Not medical advice. Plants never receive an edible verdict. "
            "No webview. No URLSession. Extra content later via Files."
        ),
        "articles": "articles.jsonl",
        "index": "inverted.json",
    }
    (PACK / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    (PACK / "README.md").write_text(
        """# GuidePack

Bundled field articles for the Field tab ask-engine.

- `articles.jsonl` — real wilderness copy, not lorem
- `inverted.json` — term → article id term-frequency
- No network. No edible plant verdicts. First aid is not medical advice.

Verify in the built app:

```bash
test -f "$APP/GuidePack/manifest.json" && wc -l "$APP/GuidePack/articles.jsonl"
```
"""
    )
    print(f"GuidePack: {len(records)} articles -> {PACK}")


if __name__ == "__main__":
    main()
