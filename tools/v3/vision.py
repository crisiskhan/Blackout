"""Vision labels per state + lookalikes. NEVER edible unlock."""
from __future__ import annotations

from .common import ROOT, write_json


def lab(
    lid: str,
    name: str,
    name_es: str,
    kind: str,
    lookalikes: list[str],
    leave: bool,
    note: str,
    note_es: str,
    marine_fl: bool = False,
) -> dict:
    return {
        "id": lid,
        "name": {"en": name, "es": name_es},
        "kind": kind,
        "lookalikes": lookalikes,
        "leaveIt": leave,
        "edibleUnlock": False,
        "marineOrGatorFL": marine_fl,
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
        lab("tx-prickly-pear", "Prickly pear", "Nopal", "cactus", ["glochid-lookalike"], False, "Spines and glochids. Vision does not unlock edible pads.", "Espinas. Vision no desbloquea nopales comestibles."),
        lab("tx-yucca", "Yucca", "Yuca", "cacti_yucca", ["sotol-lookalike", "agave-lookalike"], False, "Sharp tips. Not a salad.", "Puntas afiladas. No es ensalada."),
        lab("tx-western-diamondback", "Western diamondback", "Cascabel diamante occidental", "snake", ["bullsnake-lookalike", "gophersnake-lookalike"], False, "Venomous. Give space.", "Venenosa. Da espacio."),
        lab("tx-copperhead", "Copperhead", "Cabeza de cobre", "snake", ["cornsnake-lookalike"], False, "Venomous. East and Hill Country.", "Venenosa. Este y Hill Country."),
        lab("tx-cottonmouth", "Cottonmouth", "Boca de algodón", "snake", ["watersnake-lookalike"], False, "Venomous. Water edges in east TX.", "Venenosa. Orillas en el este de TX."),
        lab("tx-coyote", "Coyote", "Coyote", "mammal", ["dog-lookalike"], False, "Wild canid. Do not feed.", "Cánido silvestre. No alimentes."),
        lab("tx-javelina", "Javelina", "Pecari", "mammal", ["feral-hog-lookalike"], False, "Charges when cornered.", "Embiste si se siente acorralado."),
        lab("tx-whitetail", "White-tailed deer", "Venado cola blanca", "mammal", ["mule-deer-lookalike"], False, "Road and dusk hazard.", "Peligro en carretera y al anochecer."),
        *fungi_leave_set("tx"),
    ]


def nm_labels() -> list[dict]:
    return [
        lab("nm-pinon", "Piñon", "Piñón", "tree", ["juniper-lookalike"], False, "High desert tree.", "Árbol de desierto alto."),
        lab("nm-juniper", "Juniper", "Enebro", "tree", ["pinon-lookalike"], False, "Scale leaves, berry-like cones.", "Hojas en escama."),
        lab("nm-aspen", "Aspen", "Álamo temblón", "tree", ["cottonwood-lookalike"], False, "High country.", "Alta montaña."),
        lab("nm-cottonwood", "Rio Grande cottonwood", "Álamo del Río Grande", "tree", ["aspen-lookalike"], False, "Bosque tree.", "Árbol de bosque ribereño."),
        lab("nm-cholla", "Cholla", "Cholla", "cactus", ["prickly-pear-lookalike"], False, "Joints hitchhike on skin.", "Los segmentos se pegan a la piel."),
        lab("nm-yucca", "Yucca", "Yuca", "cacti_yucca", ["sotol-lookalike"], False, "Sharp tips.", "Puntas afiladas."),
        lab("nm-sotol", "Sotol", "Sotol", "cacti_yucca", ["yucca-lookalike"], False, "Desert rosette.", "Roseta del desierto."),
        lab("nm-prairie-rattler", "Prairie rattlesnake", "Cascabel de pradera", "snake", ["bullsnake-lookalike"], False, "Venomous. Give space.", "Venenosa. Da espacio."),
        lab("nm-western-diamondback", "Western diamondback", "Cascabel diamante occidental", "snake", ["gophersnake-lookalike"], False, "Venomous. Southern NM.", "Venenosa. Sur de NM."),
        lab("nm-elk", "Elk", "Wapití", "mammal", ["mule-deer-lookalike"], False, "Rut is a hazard.", "El celo es un peligro."),
        lab("nm-mule-deer", "Mule deer", "Venado bura", "mammal", ["whitetail-lookalike"], False, "Dusk roads.", "Carreteras al anochecer."),
        lab("nm-black-bear", "Black bear", "Oso negro", "mammal", ["dark-dog-lookalike"], False, "Food storage, not photos.", "Guarda comida, no fotos."),
        *fungi_leave_set("nm"),
    ]


def fl_labels() -> list[dict]:
    return [
        lab("fl-live-oak", "Live oak", "Encino siempreverde", "tree", ["laurel-oak-lookalike"], False, "Coastal plain oak.", "Encino de la planicie costera."),
        lab("fl-slash-pine", "Slash pine", "Pino elliotti", "tree", ["longleaf-lookalike"], False, "Flatwoods.", "Pinares húmedos."),
        lab("fl-sabal", "Sabal palm", "Palma sabal", "tree", ["coconut-lookalike"], False, "State tree. Not a coconut unlock.", "Árbol del estado. No desbloquea coco."),
        lab("fl-cypress", "Bald cypress", "Ciprés calvo", "tree", ["dawn-redwood-lookalike"], False, "Knees in water.", "Rodillas en el agua."),
        lab("fl-eastern-diamondback", "Eastern diamondback", "Cascabel diamante oriental", "snake", ["pinesnake-lookalike"], False, "Venomous.", "Venenosa."),
        lab("fl-cottonmouth", "Cottonmouth", "Boca de algodón", "snake", ["banded-watersnake-lookalike"], False, "Venomous. Water edges.", "Venenosa. Orillas."),
        lab("fl-coral", "Coral snake", "Coralillo", "snake", ["scarlet-kingsnake-lookalike"], False, "Venomous. Do not use rhyme as ID.", "Venenosa. No uses rimas como ID."),
        lab("fl-gator", "American alligator", "Caimán americano", "marine_gator", ["crocodile-lookalike"], False, "FL only. Dusk edge hunter.", "Solo FL. Caza la orilla al anochecer.", True),
        lab("fl-manatee", "Manatee", "Manatí", "marine_gator", ["dolphin-lookalike"], False, "Marine mammal. Do not chase.", "Mamífero marino. No persigas.", True),
        lab("fl-dolphin", "Bottlenose dolphin", "Delfín nariz de botella", "marine_gator", ["manatee-lookalike"], False, "Marine. Do not feed.", "Marino. No alimentes.", True),
        lab("fl-raccoon", "Raccoon", "Mapache", "mammal", ["cat-lookalike"], False, "Rabies vector. Do not handle.", "Vector de rabia. No lo tomes."),
        lab("fl-armadillo", "Nine-banded armadillo", "Armadillo", "mammal", ["possum-lookalike"], False, "Night digger.", "Excava de noche."),
        *fungi_leave_set("fl"),
    ]


def ny_labels() -> list[dict]:
    return [
        lab("ny-sugar-maple", "Sugar maple", "Arce azucarero", "tree", ["norway-maple-lookalike"], False, "Northeast hardwood.", "Madera dura del noreste."),
        lab("ny-white-oak", "White oak", "Roble blanco", "tree", ["chestnut-oak-lookalike"], False, "Lobed leaves.", "Hojas lobuladas."),
        lab("ny-hemlock", "Eastern hemlock", "Tsuga del este", "tree", ["balsam-lookalike"], False, "Shade evergreen.", "Siempreverde de sombra."),
        lab("ny-white-pine", "Eastern white pine", "Pino blanco", "tree", ["red-pine-lookalike"], False, "Five needles.", "Cinco agujas."),
        lab("ny-timber-rattler", "Timber rattlesnake", "Cascabel de bosque", "snake", ["milksnake-lookalike"], False, "Venomous. Upstate / ledges.", "Venenosa. Norte del estado."),
        lab("ny-copperhead", "Copperhead", "Cabeza de cobre", "snake", ["watersnake-lookalike"], False, "Venomous. Hudson / ledges.", "Venenosa. Hudson / cornisas."),
        lab("ny-black-bear", "Black bear", "Oso negro", "mammal", ["dark-dog-lookalike"], False, "Adirondack and Catskill.", "Adirondacks y Catskills."),
        lab("ny-whitetail", "White-tailed deer", "Venado cola blanca", "mammal", ["dog-lookalike"], False, "Tick host. Dusk roads.", "Hospedero de garrapatas."),
        lab("ny-moose", "Moose", "Alce", "mammal", ["elk-lookalike"], False, "Adirondack. Do not approach calves.", "Adirondacks. No te acerques a las crías."),
        *fungi_leave_set("ny"),
    ]


def write_all() -> None:
    root = ROOT / "Resources" / "Vision"
    mapping = {"TX": tx_labels(), "NM": nm_labels(), "FL": fl_labels(), "NY": ny_labels()}
    for state, labels in mapping.items():
        kinds = {l["kind"] for l in labels}
        assert "fungi" in kinds
        if state == "FL":
            assert any(l["marineOrGatorFL"] for l in labels)
        else:
            assert not any(l["marineOrGatorFL"] for l in labels)
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
