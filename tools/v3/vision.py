"""Vision labels per state + lookalikes. NEVER edible unlock.

Only states we ship a map pack for get a label book: TX and NM. A book for
ground the phone cannot draw is a promise the vessel cannot keep.
"""
from __future__ import annotations

from .common import ROOT, write_json

SHIPPED_STATES = ("TX", "NM")


def lab(
    lid: str,
    name: str,
    name_es: str,
    kind: str,
    lookalikes: list[str],
    leave: bool,
    note: str,
    note_es: str,
) -> dict:
    return {
        "id": lid,
        "name": {"en": name, "es": name_es},
        "kind": kind,
        "lookalikes": lookalikes,
        "leaveIt": leave,
        "edibleUnlock": False,
        "honesty": {
            "en": "Vision is a guess. Percent is not ID. " + note,
            "es": "Vision es una conjetura. El porcentaje no es identificación. " + note_es,
        },
    }


def fungi_leave_set(prefix: str) -> list[dict]:
    return [
        lab(f"{prefix}-amanita", "Amanita-like cap", "Sombrero tipo Amanita", "fungi", ["destroying-angel-lookalike", "puffball-young"], True, "Default LEAVE IT.", "Por defecto DÉJALO."),
        lab(f"{prefix}-galerina", "Little brown mushroom", "Hongo marrón chico", "fungi", ["galerina-lookalike", "honey-mushroom-lookalike"], True, "LBMs are a leave-it set.", "Los marrones chicos se dejan."),
        lab(f"{prefix}-false-morel", "Brain / false morel shape", "Forma de falsa colmenilla", "fungi", ["true-morel-lookalike"], True, "Do not eat. Late liver toxins exist.", "No comas. Hay toxinas tardías de hígado."),
        lab(f"{prefix}-jack", "Jack-o-lantern / orange shelf", "Naranja en estante", "fungi", ["chanterelle-lookalike"], True, "Leave it. GI wreck is common in lookalikes.", "Déjalo. Los parecidos destrozan el estómago."),
    ]


def tx_labels() -> list[dict]:
    return [
        lab("tx-live-oak", "Live oak", "Encino siempreverde", "tree", ["white-oak-lookalike"], False, "Common Texas shade tree.", "Árbol de sombra común en Texas."),
        lab("tx-mesquite", "Mesquite", "Mezquite", "tree", ["acacia-lookalike"], False, "Thorns. Not a meal ticket.", "Espinas. No es un ticket de comida."),
        lab("tx-cedar-elm", "Cedar elm", "Olmo cedro", "tree", ["american-elm-lookalike"], False, "Street and bosque tree.", "Árbol de calle y bosque."),
        lab("tx-pecan", "Pecan", "Nogal pecanero", "tree", ["hickory-lookalike"], False, "Cultivated and wild along rivers.", "Cultivado y silvestre junto a ríos."),
        lab("tx-cottonwood", "Cottonwood", "Álamo", "tree", ["aspen-lookalike"], False, "Bosque and river tree.", "Árbol de bosque y río."),
        lab("tx-loblolly", "Loblolly pine", "Pino taeda", "tree", ["shortleaf-lookalike"], False, "East Texas and Lost Pines.", "Este de Texas y Lost Pines."),
        lab("tx-prickly-pear", "Prickly pear", "Nopal", "cactus", ["glochid-lookalike"], False, "Spines and glochids. A guess is not a name.", "Espinas. Una conjetura no es un nombre."),
        lab("tx-yucca", "Yucca", "Yuca", "cacti_yucca", ["sotol-lookalike", "agave-lookalike"], False, "Sharp tips. Not a salad.", "Puntas afiladas. No es ensalada."),
        lab("tx-western-diamondback", "Western diamondback", "Cascabel diamante occidental", "snake", ["bullsnake-lookalike", "gophersnake-lookalike"], False, "Venomous. Give space.", "Venenosa. Da espacio."),
        lab("tx-copperhead", "Copperhead", "Cabeza de cobre", "snake", ["cornsnake-lookalike"], False, "Venomous. East and Hill Country.", "Venenosa. Este y Hill Country."),
        lab("tx-cottonmouth", "Cottonmouth", "Boca de algodón", "snake", ["watersnake-lookalike"], False, "Venomous. Water edges in east TX.", "Venenosa. Orillas en el este de TX."),
        lab("tx-coyote", "Coyote", "Coyote", "mammal", ["dog-lookalike"], False, "Wild canid. Do not feed.", "Cánido silvestre. No alimentes."),
        lab("tx-javelina", "Javelina", "Pecari", "mammal", ["feral-hog-lookalike"], False, "Charges when cornered.", "Embiste si se siente acorralado."),
        lab("tx-whitetail", "White-tailed deer", "Venado cola blanca", "mammal", ["mule-deer-lookalike"], False, "Road and dusk hazard.", "Peligro en carretera y al anochecer."),
        lab("tx-hog", "Feral hog", "Cerdo asilvestrado", "mammal", ["javelina-lookalike"], False, "Charges when cornered. East Texas.", "Embiste si se siente acorralado. Este de Texas."),
        lab("tx-jackrabbit", "Jackrabbit", "Liebre", "mammal", ["cottontail-lookalike"], False, "Dusk roads.", "Carreteras al anochecer."),
        lab("tx-raccoon", "Raccoon", "Mapache", "mammal", ["coatimundi-lookalike"], False, "Night camp thief. Do not feed.", "Ladrón de campamento. No alimentes."),
        lab("tx-skunk", "Skunk", "Zorrillo", "mammal", ["polecat-lookalike"], False, "Give space. Spray is not a bite.", "Da espacio. El chorro no es mordida."),
        lab("tx-armadillo", "Armadillo", "Armadillo", "mammal", ["pangolin-lookalike"], False, "Night road hazard.", "Peligro nocturno en carretera."),
        lab("tx-fox", "Fox", "Zorro", "mammal", ["coyote-lookalike"], False, "Do not feed.", "No alimentes."),
        lab("tx-squirrel", "Squirrel", "Ardilla", "mammal", ["rat-lookalike"], False, "Give space.", "Da espacio."),
        lab("tx-bobcat", "Bobcat", "Lince rojo", "mammal", ["lynx-lookalike"], False, "Give space. Do not corner it.", "Da espacio. No lo acorrales."),
        lab("tx-turkey", "Turkey", "Pavo", "bird", ["vulture-lookalike"], False, "A still is a guess. Already-have is the bird card.", "Una foto es una conjetura. Si ya lo tienes, la tarjeta de ave."),
        lab("tx-quail", "Quail", "Codorniz", "bird", ["dove-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("tx-dove", "Dove", "Paloma", "bird", ["pigeon-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("tx-roadrunner", "Roadrunner", "Correcaminos", "bird", ["cuckoo-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("tx-hawk", "Hawk", "Halcón", "bird", ["eagle-lookalike"], True, "Raptor. Leave it.", "Rapaz. Déjalo."),
        lab("tx-owl", "Owl", "Búho", "bird", ["hawk-lookalike"], True, "Raptor. Leave it.", "Rapaz. Déjalo."),
        lab("tx-duck", "Duck", "Pato", "bird", ["goose-lookalike"], False, "Water bird. Already-have is the bird card.", "Ave de agua. Si ya lo tienes, la tarjeta de ave."),
        lab("tx-vulture", "Vulture", "Zopilote", "bird", ["eagle-lookalike"], True, "Scavenger. Leave it.", "Carroñero. Déjalo."),
        lab("tx-raven", "Raven", "Cuervo", "bird", ["crow-lookalike"], True, "Scavenger. Leave it.", "Carroñero. Déjalo."),
        lab("tx-bass", "Bass", "Lobina", "fish", ["sunfish-lookalike"], False, "Already-have is the fish card.", "Si ya lo tienes, la tarjeta de pez."),
        lab("tx-catfish", "Catfish", "Bagre", "fish", ["bullhead-lookalike"], False, "Skin it. Cook through.", "Pélalo. Cocina completo."),
        lab("tx-sunfish", "Sunfish", "Mojarra", "fish", ["bass-lookalike"], False, "Already-have is the fish card.", "Si ya lo tienes, la tarjeta de pez."),
        lab("tx-horned-lizard", "Horned lizard", "Camaleón", "lizard", ["toad-lookalike"], True, "Not food. Leave it.", "No es comida. Déjalo."),
        lab("tx-softshell", "Softshell", "Tortuga de caparazón blando", "turtle", ["slider-lookalike"], False, "Already-have is the turtle card. Box turtle is not food.", "Si ya la tienes, la tarjeta de tortuga. La de caja no es comida."),
        lab("tx-box-turtle", "Box turtle", "Tortuga de caja", "turtle", ["slider-lookalike"], True, "Not food. Leave it.", "No es comida. Déjala."),
        lab("tx-toad", "Toad", "Sapo", "frog", ["frog-lookalike"], True, "Bufotoxin. Leave it.", "Bufotoxina. Déjalo."),
        lab("tx-bullfrog", "Bullfrog", "Rana toro", "frog", ["toad-lookalike"], True, "A still cannot tell toad from frog. Leave it.", "Una foto no distingue sapo de rana. Déjala."),
        *fungi_leave_set("tx"),
    ]


def nm_labels() -> list[dict]:
    return [
        lab("nm-pinon", "Piñon", "Piñón", "tree", ["juniper-lookalike"], False, "High desert tree.", "Árbol de desierto alto."),
        lab("nm-juniper", "Juniper", "Enebro", "tree", ["pinon-lookalike"], False, "Scale leaves, berry-like cones.", "Hojas en escama."),
        lab("nm-aspen", "Aspen", "Álamo temblón", "tree", ["cottonwood-lookalike"], False, "High country.", "Alta montaña."),
        lab("nm-cottonwood", "Rio Grande cottonwood", "Álamo del Río Grande", "tree", ["aspen-lookalike"], False, "Bosque tree.", "Árbol de bosque ribereño."),
        lab("nm-ponderosa", "Ponderosa pine", "Pino ponderosa", "tree", ["pinon-lookalike"], False, "High country pine.", "Pino de alta montaña."),
        lab("nm-cholla", "Cholla", "Cholla", "cactus", ["prickly-pear-lookalike"], False, "Joints hitchhike on skin. Not food.", "Los segmentos se pegan a la piel. No es comida."),
        lab("nm-prickly-pear", "Prickly pear", "Nopal", "cactus", ["cholla-lookalike"], False, "Spines and glochids. A guess is not a name.", "Espinas. Una conjetura no es un nombre."),
        lab("nm-yucca", "Yucca", "Yuca", "cacti_yucca", ["sotol-lookalike"], False, "Sharp tips.", "Puntas afiladas."),
        lab("nm-sotol", "Sotol", "Sotol", "cacti_yucca", ["yucca-lookalike"], False, "Desert rosette. Not a Field meal ticket.", "Roseta del desierto. No es un ticket de Field."),
        lab("nm-prairie-rattler", "Prairie rattlesnake", "Cascabel de pradera", "snake", ["bullsnake-lookalike"], False, "Venomous. Give space.", "Venenosa. Da espacio."),
        lab("nm-western-diamondback", "Western diamondback", "Cascabel diamante occidental", "snake", ["gophersnake-lookalike"], False, "Venomous. Southern NM.", "Venenosa. Sur de NM."),
        lab("nm-elk", "Elk", "Wapití", "mammal", ["mule-deer-lookalike"], False, "Rut is a hazard.", "El celo es un peligro."),
        lab("nm-mule-deer", "Mule deer", "Venado bura", "mammal", ["whitetail-lookalike"], False, "Dusk roads.", "Carreteras al anochecer."),
        lab("nm-black-bear", "Black bear", "Oso negro", "mammal", ["dark-dog-lookalike"], False, "Food storage, not photos.", "Guarda comida, no fotos."),
        lab("nm-coyote", "Coyote", "Coyote", "mammal", ["dog-lookalike"], False, "Wild canid. Do not feed.", "Cánido silvestre. No alimentes."),
        lab("nm-pronghorn", "Pronghorn", "Berrendo", "mammal", ["deer-lookalike"], False, "Dusk roads.", "Carreteras al anochecer."),
        lab("nm-jackrabbit", "Jackrabbit", "Liebre", "mammal", ["cottontail-lookalike"], False, "Dusk roads.", "Carreteras al anochecer."),
        lab("nm-squirrel", "Squirrel", "Ardilla", "mammal", ["rat-lookalike"], False, "Give space.", "Da espacio."),
        lab("nm-fox", "Fox", "Zorro", "mammal", ["coyote-lookalike"], False, "Do not feed.", "No alimentes."),
        lab("nm-turkey", "Turkey", "Pavo", "bird", ["vulture-lookalike"], False, "A still is a guess. Already-have is the bird card.", "Una foto es una conjetura. Si ya lo tienes, la tarjeta de ave."),
        lab("nm-quail", "Quail", "Codorniz", "bird", ["dove-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("nm-dove", "Dove", "Paloma", "bird", ["pigeon-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("nm-roadrunner", "Roadrunner", "Correcaminos", "bird", ["cuckoo-lookalike"], False, "Give it the air.", "Cede el aire."),
        lab("nm-hawk", "Hawk", "Halcón", "bird", ["eagle-lookalike"], True, "Raptor. Leave it.", "Rapaz. Déjalo."),
        lab("nm-eagle", "Eagle", "Águila", "bird", ["hawk-lookalike"], True, "Raptor. Leave it.", "Rapaz. Déjalo."),
        lab("nm-duck", "Duck", "Pato", "bird", ["goose-lookalike"], False, "Water bird. Already-have is the bird card.", "Ave de agua. Si ya lo tienes, la tarjeta de ave."),
        lab("nm-raven", "Raven", "Cuervo", "bird", ["crow-lookalike"], True, "Scavenger. Leave it.", "Carroñero. Déjalo."),
        lab("nm-trout", "Trout", "Trucha", "fish", ["whitefish-lookalike"], False, "Already-have is the fish card.", "Si ya lo tienes, la tarjeta de pez."),
        lab("nm-catfish", "Catfish", "Bagre", "fish", ["bullhead-lookalike"], False, "Skin it. Cook through.", "Pélalo. Cocina completo."),
        lab("nm-gila", "Gila monster", "Monstruo de Gila", "lizard", ["skink-lookalike"], True, "Venomous. Leave it.", "Venenoso. Déjalo."),
        lab("nm-horned-lizard", "Horned lizard", "Camaleón", "lizard", ["toad-lookalike"], True, "Not food. Leave it.", "No es comida. Déjalo."),
        lab("nm-turtle", "Turtle", "Tortuga", "turtle", ["tortoise-lookalike"], False, "Already-have is the turtle card. Box turtle is not food.", "Si ya la tienes, la tarjeta de tortuga. La de caja no es comida."),
        lab("nm-toad", "Toad", "Sapo", "frog", ["frog-lookalike"], True, "Bufotoxin. Leave it.", "Bufotoxina. Déjalo."),
        *fungi_leave_set("nm"),
    ]


def write_all() -> None:
    root = ROOT / "Resources" / "Vision"
    mapping = {"TX": tx_labels(), "NM": nm_labels()}
    assert tuple(mapping) == SHIPPED_STATES
    for stale in root.glob("labels.*.json"):
        if stale.stem.split(".")[-1].upper() not in SHIPPED_STATES:
            stale.unlink()
    for state, labels in mapping.items():
        kinds = {l["kind"] for l in labels}
        assert "fungi" in kinds
        write_json(
            root / f"labels.{state.lower()}.json",
            {
                "state": state,
                "neverEdibleUnlock": True,
                "fungiDefault": "LEAVE_IT",
                "labels": labels,
            },
        )
    write_json(
        root / "lookalikes.json",
        {
            "rule": "Every positive guess lists lookalikes. Percent is not ID. edibleUnlock is always false.",
        },
    )
    print("vision labels written")
