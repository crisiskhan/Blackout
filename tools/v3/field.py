"""Generate field.core + per-state Field JSON (v1.4 schema, EN+ES).

Only states with a bundled map pack get a book. A card for ground the phone
cannot draw is advice with no map behind it.
"""
from __future__ import annotations

from .common import ROOT, diagram_png, write_json

SHIPPED_STATES = ("TX", "NM")
CATEGORIES = [
    "medical",
    "trauma",
    "environment",
    "water",
    "fire",
    "shelter",
    "nav",
    "plants",
    "animals",
    "fungi",
    "food",
    "signaling",
    "tactics",
]


def step(do: str, why: str, child: str, stop: str, image: str, do_es: str, why_es: str, child_es: str, stop_es: str, tick_s: int | None = None, metronome_bpm: int | None = None, party: dict | None = None) -> dict:
    out = {
        "do": {"en": do, "es": do_es},
        "why": {"en": why, "es": why_es},
        "child": {"en": child, "es": child_es},
        "stop": {"en": stop, "es": stop_es},
        "image": image,
    }
    if tick_s is not None:
        out["tickSeconds"] = tick_s
    if metronome_bpm is not None:
        out["metronomeBpm"] = metronome_bpm
    if party:
        out["party"] = party
    return out


def card(
    cid: str,
    category: str,
    title: str,
    title_es: str,
    situation: str,
    situation_es: str,
    stop_if: list[tuple[str, str]],
    get_to_care: str,
    get_to_care_es: str,
    steps: list[dict],
    states: list[str] | None = None,
    speak: bool = True,
    packs: list[str] | None = None,
) -> dict:
    out = {
        "schema": "1.4",
        "id": cid,
        "category": category,
        "states": states or list(SHIPPED_STATES),
        "title": {"en": title, "es": title_es},
        "situation": {"en": situation, "es": situation_es},
        "stop_if": [{"en": a, "es": b} for a, b in stop_if],
        "get_to_care": {"en": get_to_care, "es": get_to_care_es},
        "speak": speak,
        "sendToParty": True,
        "steps": steps,
    }
    if packs:
        out["packs"] = packs
    return out


def packs_for(cid: str) -> list[str] | None:
    """East and west Texas share a state book. Range cards name the pack."""
    if cid.startswith("tx-east-"):
        return ["tx-east"]
    if cid in {"tx-tree-use", "tx-mammal", "tx-game", "tx-snake"}:
        return ["tx-west"]
    return None


def core_cards() -> list[dict]:
    cards = []
    cards.append(
        card(
            "med-cpr-adult",
            "medical",
            "Adult CPR",
            "RCP adulto",
            "Unresponsive adult, not breathing normally. You are with the party and a phone may or may not reach 911.",
            "Adulto sin respuesta, no respira con normalidad. Estás con el grupo y el teléfono puede o no alcanzar al 911.",
            [
                ("The person starts breathing normally and has a pulse you can feel.", "La persona respira con normalidad y tiene pulso."),
                ("Scene becomes unsafe (fire, collapse, traffic).", "La escena se vuelve insegura."),
                ("You are too exhausted to continue and no one can take over.", "Estás agotado y nadie puede relevarte."),
            ],
            "Get trained help and an AED.",
            "Consigue ayuda entrenada y un DEA.",
            [
                step(
                    "Check response and look at the chest for 10 seconds. If no normal breathing, start compressions.",
                    "Delay kills. Gasping is not normal breathing.",
                    "Keep children back. One adult does compressions; another watches the child.",
                    "If they cough, move, or breathe normally, stop compressions and watch the airway.",
                    "cpr-check.png",
                    "Comprueba respuesta y mira el pecho 10 segundos. Si no hay respiración normal, empieza compresiones.",
                    "La demora mata. El jadeo no es respiración normal.",
                    "Aleja a los niños. Un adulto comprime; otro vigila al niño.",
                    "Si tose, se mueve o respira normal, detén y vigila la vía aérea.",
                    tick_s=10,
                ),
                step(
                    "Hard, fast compressions in the center of the chest. 100–120 per minute. Let the chest recoil.",
                    "Blood has to reach the brain. Shallow pumps do nothing.",
                    "Do not let a child stand on the chest or 'help' compressions.",
                    "Stop if an AED is attached and tells you to stay clear, or if they start breathing.",
                    "cpr-compress.png",
                    "Compresiones fuertes y rápidas al centro del pecho. 100–120 por minuto. Deja que el pecho recoja.",
                    "La sangre tiene que llegar al cerebro. Las palmaditas no sirven.",
                    "No dejes que un niño se suba al pecho ni 'ayude' a comprimir.",
                    "Para si el DEA dice apartarse o si empieza a respirar.",
                    metronome_bpm=110,
                    party={"1": "You do continuous compressions.", "2": "Swap every 2 minutes.", "4": "Compress / air / AED / crowd control."},
                ),
                step(
                    "If trained and willing, 30:2 breaths. If not, hands-only until help or exhaustion.",
                    "Oxygen helps, but bad breaths delay pumps. Hands-only is valid.",
                    "Do not put a child's mouth on a stranger. Adult-only breaths.",
                    "Stop breaths if vomit fills the mouth — roll and clear, then resume pumps.",
                    "cpr-breath.png",
                    "Si estás entrenado, 30:2. Si no, solo manos hasta relevo o agotamiento.",
                    "El oxígeno ayuda, pero una mala insuflación retrasa las bombas.",
                    "No pongas la boca de un niño en un extraño. Solo adultos.",
                    "Si hay vómito, gira, limpia y reanuda bombas.",
                    tick_s=120,
                ),
            ],
        )
    )
    cards.append(
        card(
            "med-bleed-pack",
            "trauma",
            "Pack a bad bleed",
            "Taponar una hemorragia grave",
            "Blood is pulsing or soaking through cloth faster than you can wipe it. Limb or junction (groin, armpit, neck).",
            "La sangre pulsa o empapa la tela más rápido de lo que puedes limpiar. Extremidad o unión (ingle, axila, cuello).",
            [
                ("Bleeding stops and the person is alert.", "El sangrado para y la persona está alerta."),
                ("You cannot see the wound and they are in a moving vehicle wreck — stabilize first.", "No ves la herida y hay un choque inestable: primero estabiliza."),
            ],
            "This is a race to a hospital. Use Emergency SOS when a net exists. Do not sit on this card.",
            "Es una carrera al hospital. Usa Emergency SOS si hay red. No te quedes en esta tarjeta.",
            [
                step(
                    "Expose the wound. Feed gauze or clean cloth straight into the hole. Press hard with both hands.",
                    "Surface wipes do not close a vessel. Pressure has to be on the bleeder.",
                    "A child can hold unused gauze. They do not push into the wound.",
                    "If you see bone end or a chest suck, this is not a simple pack — go to chest/open-fracture cards.",
                    "bleed-pack.png",
                    "Expón la herida. Mete gasa o tela limpia en el hueco. Presiona con las dos manos.",
                    "Limpiar la superficie no cierra un vaso. La presión va sobre el sangrado.",
                    "Un niño puede sostener gasa. No empuja dentro de la herida.",
                    "Si ves hueso o el pecho chupa aire, no es un taponado simple.",
                    party={"1": "You pack and hold.", "2": "One packs, one lifts/holds limb.", "4": "Pack / hold / kit / watch the trail."},
                ),
                step(
                    "If a limb and blood still pours, place a windlass tourniquet 5–7 cm above the wound, not on a joint. Twist until bleeding slows, note the time.",
                    "A loose strap is jewelry. Tight enough that a finger cannot slip under.",
                    "Tell the child the strap will hurt and that hurting means it is working.",
                    "Do not put a tourniquet on the neck. Do not loosen it to 'check'.",
                    "bleed-tq.png",
                    "Si es extremidad y sigue saliendo, torniquete 5–7 cm arriba, no en articulación. Anota la hora.",
                    "Una correa floja es adorno. Tan apretada que no quepa un dedo.",
                    "Dile al niño que dolerá y que el dolor significa que funciona.",
                    "Nunca en el cuello. No lo aflojes para 'mirar'.",
                    tick_s=60,
                ),
            ],
        )
    )
    cards.append(
        card(
            "env-heat-collapse",
            "environment",
            "Heat collapse",
            "Colapso por calor",
            "Party member stopped sweating or is confused, hot, and not making sense after work in heat.",
            "Alguien del grupo dejó de sudar o está confuso, caliente y sin sentido después de trabajar con calor.",
            [
                ("They cool, talk sense, and can drink.", "Se enfría, habla con sentido y puede beber."),
                ("Seizure starts — protect the head, do not pour water into the mouth.", "Empieza una convulsión: protege la cabeza, no eches agua en la boca."),
            ],
            "Heat stroke is an emergency. Cool first, then move to care. Do not wait for 'feeling better' in the sun.",
            "El golpe de calor es una emergencia. Enfría primero, luego mueve a cuidado.",
            [
                step(
                    "Get them to shade. Strip extra layers. Pour water on skin and fan. Ice packs at neck, armpits, groin if you have them.",
                    "The brain is cooking. Evaporative cooling is the field tool.",
                    "Keep a child in shade with the same cooling. Do not make them 'walk it off'.",
                    "Stop oral fluids if they cannot swallow or are vomiting continuously.",
                    "heat-cool.png",
                    "A la sombra. Quita capas. Agua en la piel y abanica. Hielo en cuello, axilas e ingle si hay.",
                    "El cerebro se está cociendo. El enfriamiento evaporativo es la herramienta.",
                    "El niño también a la sombra. No lo hagas 'caminar'.",
                    "Nada por boca si no traga o vomita sin parar.",
                    tick_s=600,
                    party={"1": "Cool and watch airway.", "2": "One cools, one fetches water/shade.", "4": "Cool / water / shade tarp / watch others."},
                )
            ],
        )
    )
    cards.append(
        card(
            "water-disinfect",
            "water",
            "Make water less bad",
            "Hacer el agua menos mala",
            "You need drinking water from a creek, tank, or unknown tap. No lab, no live test.",
            "Necesitas beber de un arroyo, tanque o grifo desconocido. Sin laboratorio.",
            [
                ("You have sealed commercial water.", "Tienes agua comercial sellada."),
                ("The source is downstream of a carcass, sewage outfall, or chemical sheen — walk farther.", "La fuente está abajo de un cadáver, alcantarilla o brillo químico: camina más."),
            ],
            "Disinfection is not sterile. GI illness still happens. Get to care for bloody stool, no urine, or confusion.",
            "Desinfectar no es estéril. Aún puedes enfermar. Busca cuidado si hay sangre en heces, no orinas o hay confusión.",
            [
                step(
                    "Clear first: settle, then filter cloth. Boil a rolling boil for 1 minute (3 minutes above ~2000 m).",
                    "Cloud hides bugs. Heat is the honest field kill for most pathogens.",
                    "Do not let a child sip the untreated scoop 'to try'.",
                    "Stop if the water smells like fuel or has a rainbow sheen — boiling will not fix chemicals.",
                    "water-boil.png",
                    "Aclara: deja asentar, filtra con tela. Hierve 1 minuto (3 minutos sobre ~2000 m).",
                    "El agua turbia esconde bichos. El calor es la muerte honesta de campo.",
                    "El niño no prueba el scoop sin tratar.",
                    "Para si huele a combustible o hay irisado: el hervor no quita químicos.",
                    tick_s=60,
                    party={"1": "1 L per person per hour of work as a starting guess.", "2": "2 L pot, take turns watching the boil.", "4": "4 L rotation; one person never leaves the stove."},
                )
            ],
        )
    )
    cards.append(
        card(
            "fire-stove",
            "fire",
            "Stove and small fire",
            "Estufa y fuego pequeño",
            "You need heat for water or warmth. Wind, dry grass, or a canyon can turn a cook fire into a problem.",
            "Necesitas calor para agua o abrigo. Viento, pasto seco o un cañón pueden convertir la cocina en un problema.",
            [
                ("You have a working canister stove on mineral soil.", "Tienes estufa de cartucho sobre suelo mineral."),
                ("Red-flag wind or a fire ban you already know — do not start a new fire.", "Viento extremo o veda que ya conoces: no inicies fuego."),
            ],
            "Burns go to care. This card is for starting and killing a small fire, not fighting a wildfire.",
            "Las quemaduras van a cuidado. Esta tarjeta es para prender y matar un fuego chico, no un incendio.",
            [
                step(
                    "Mineral soil, rock ring or stove. Downwind of tents. Water or dirt in hand before the match.",
                    "Escape paths and a kill method come first.",
                    "Child stays outside the ring. They can fetch dead twigs, not tend the flame.",
                    "Stop if embers run into grass you cannot stamp.",
                    "fire-ring.png",
                    "Suelo mineral, aro de piedra o estufa. Aguas abajo de las tiendas. Agua o tierra en la mano antes del fósforo.",
                    "Primero la salida y cómo matarlo.",
                    "El niño fuera del aro. Puede traer ramitas, no cuida la llama.",
                    "Para si las brasas se van al pasto y no puedes pisarlas.",
                )
            ],
        )
    )
    cards.append(
        card(
            "shelter-tarp",
            "shelter",
            "Tarp or debris lean-to",
            "Lona o refugio de restos",
            "Night, wind, or rain is coming and you need a roof for the party.",
            "Viene noche, viento o lluvia y el grupo necesita techo.",
            [
                ("You already have a closed tent on high ground.", "Ya tienes tienda cerrada en alto."),
                ("Lightning is on top of you — get off ridges, do not hold poles.", "El rayo está encima: baja de filos, no sostengas postes."),
            ],
            "Hypothermia care if shivering stops and speech slurs. Shelter is not treatment.",
            "Cuidado por hipotermia si deja de temblar y habla raro. El refugio no es tratamiento.",
            [
                step(
                    "Pick high, drained ground. Ridgepole or taut ridgeline. Low side into the wind. Insulate the floor with pack, sit pad, or debris.",
                    "Wind and ground suck heat faster than air.",
                    "Put the child in the middle, off the dirt, not at the dripping edge.",
                    "Stop and move if water is already running under the floor.",
                    "shelter-tarp.png",
                    "Suelo alto y drenado. Cumbrera tensa. Lado bajo contra el viento. Aísla el piso.",
                    "El viento y el suelo quitan calor más que el aire.",
                    "El niño al centro, no en el borde que gotea.",
                    "Muévete si ya corre agua bajo el piso.",
                    party={"1": "One-person lean-to, 2 m ridge.", "2": "A-frame, two walls.", "4": "Tarp wall + debris bunk; one person on watch."},
                )
            ],
        )
    )
    cards.append(
        card(
            "nav-lost",
            "nav",
            "Stop and locate",
            "Parar y localizar",
            "The trail is gone, the party disagrees, or the last pip is older than your comfort.",
            "Se acabó el sendero, el grupo no está de acuerdo o el último pip es viejo.",
            [
                ("You can see a known handrail (road, river, ridge) and the party is together.", "Ves una baranda conocida y el grupo está junto."),
                ("Someone is injured — treat that first, then navigate.", "Alguien está herido: trata primero, luego navega."),
            ],
            "Walking farther while lost is how parties split. Care is the last known road or town, not a guess bearing.",
            "Caminar más estando perdido es cómo se parte el grupo. El cuidado está en el último camino conocido.",
            [
                step(
                    "STOP. Sit. Water. Mark the spot. Compare map pack, last pip, and what everyone remembers. Do not send scouts farther than voice.",
                    "Motion feels like progress and usually is not.",
                    "Give the child a job: count party, hold the whistle, sit on the pack.",
                    "Stop walking if two people have two different 'I'm sure' directions.",
                    "nav-stop.png",
                    "PARA. Siéntate. Agua. Marca el sitio. Compara el pack, el último pip y lo que recuerdan. Sin exploradores más allá de la voz.",
                    "Moverse parece progreso y casi nunca lo es.",
                    "El niño cuenta al grupo, sostiene el silbato, se sienta en la mochila.",
                    "No caminen si dos personas tienen dos 'estoy seguro' distintos.",
                    tick_s=300,
                )
            ],
        )
    )
    cards.append(
        card(
            "plant-unknown",
            "plants",
            "Unknown plant",
            "Planta desconocida",
            "Someone wants to eat, rub, or brew a plant you cannot name with certainty.",
            "Alguien quiere comer, frotar o hervir una planta que no puedes nombrar con certeza.",
            [
                ("You already have known food in the kit.", "Ya tienes comida conocida en el kit."),
                ("Lips, tongue, or skin are already burning — that is a medical card, not ID.", "Labios, lengua o piel ya arden: eso es médico, no identificación."),
            ],
            "Vision is a guess. Nothing in this app unlocks edible. If they ate it, get to care for vomiting blood, trouble breathing, or collapse.",
            "Vision es una conjetura. Nada en esta app desbloquea 'comestible'. Si ya lo comieron, busca cuidado.",
            [
                step(
                    "Do not eat it. Photo with Vision if you want a guess and lookalikes. Wash hands. Watch for rash.",
                    "Lookalikes kill. A percent is not a meal.",
                    "Take the leaf out of a child's hand. No 'tiny taste'.",
                    "Stop the experiment if anyone's mouth tingles.",
                    "plant-leave.png",
                    "No lo comas. Foto con Vision si quieres un porcentaje y parecidos. Lávate las manos.",
                    "Los parecidos matan. Un porcentaje no es una comida.",
                    "Saca la hoja de la mano del niño. Sin 'probadita'.",
                    "Para si a alguien le hormiguea la boca.",
                )
            ],
        )
    )
    cards.append(
        card(
            "animal-bite",
            "animals",
            "Bite or envenomation",
            "Mordedura o veneno",
            "Teeth, fangs, or a sting. You may or may not have seen the animal.",
            "Dientes, colmillos o aguijón. Puede que no hayas visto al animal.",
            [
                ("Tiny scratch, animal gone, person calm — wash and watch.", "Rasguño mínimo, animal lejos, persona calmada: lava y observa."),
                ("They cannot breathe or the face is swelling — this is airway, not a nature lesson.", "No puede respirar o la cara hincha: es vía aérea, no una lección de naturaleza."),
            ],
            "Antivenom and rabies decisions are hospital work. Offer Emergency SOS. Do not cut, suck, or ice a snake bite.",
            "El antiveneno y la rabia son del hospital. Ofrece Emergency SOS. No cortes, chupes ni hieles una mordedura de serpiente.",
            [
                step(
                    "Get space from the animal. Keep the person still. Remove rings. Wash with water if you can. Mark the swelling edge and time.",
                    "Motion spreads venom and panic makes hearts race.",
                    "A child stays behind an adult, not 'to see the snake'.",
                    "Stop walking them out if they are vomiting or fading — carry or wait for help.",
                    "animal-bite.png",
                    "Aléjate del animal. Quédate quieto. Quita anillos. Lava si puedes. Marca la hinchazón y la hora.",
                    "El movimiento reparte veneno y el pánico acelera el corazón.",
                    "El niño detrás de un adulto, no 'para ver la víbora'.",
                    "No los hagas caminar si vomitan o se apagan: carga o espera.",
                    tick_s=900,
                )
            ],
        )
    )
    cards.append(
        card(
            "fungi-leave",
            "fungi",
            "Fungi — leave it",
            "Hongos — déjalo",
            "A mushroom, bracket, or puffball is in the hand or in the pot.",
            "Hay un hongo, yesquero o pedo de lobo en la mano o en la olla.",
            [
                ("It is already in a sealed bag and nobody ate it — leave the bag, wash hands.", "Ya está en una bolsa y nadie lo comió: deja la bolsa, lávate."),
                ("They ate it — this is poison timing, not ID. Get to care.", "Ya lo comieron: es tiempo de veneno, no ID. Busca cuidado."),
            ],
            "Default is LEAVE IT. Vision will not unlock edible. Care for vomiting, diarrhea, or late liver pain (hours to days).",
            "Por defecto DÉJALO. Vision no desbloquea comestible. Cuidado si hay vómito, diarrea o dolor de hígado tardío.",
            [
                step(
                    "Put it down. Do not cook 'just a little'. If already eaten, save a piece in a bag for the hospital and start walking to care.",
                    "Cooking does not make a deadly mushroom safe. Some toxins show up late.",
                    "Take it out of the child's collection bucket.",
                    "Stop tasting 'to compare'. There is no field test that is honest.",
                    "fungi-leave.png",
                    "Suéltalo. No lo cocines 'un poquito'. Si ya se comió, guarda un trozo para el hospital.",
                    "Cocinar no vuelve seguro un hongo mortal. Hay toxinas tardías.",
                    "Sácalo del cubo del niño.",
                    "Nada de probar 'para comparar'. No hay test de campo honesto.",
                )
            ],
        )
    )
    cards.append(
        card(
            "food-cook",
            "food",
            "Cook what you already trust",
            "Cocina lo que ya confías",
            "You have rice, beans, a can, or a known fish you caught — not a mystery plant.",
            "Tienes arroz, frijoles, una lata o un pescado conocido que pescaste — no una planta misteriosa.",
            [
                ("Food is commercially sealed and undamaged.", "La comida es comercial, sellada e intacta."),
                ("The can is bulging or the meat smells like death — bury it, do not taste.", "La lata está abombada o la carne huele a muerte: entiérrela, no pruebes."),
            ],
            "Food poisoning is care if they cannot keep fluids down. This card does not ID wild plants.",
            "La intoxicación va a cuidado si no retienen líquidos. Esta tarjeta no identifica plantas silvestres.",
            [
                step(
                    "Boil. Keep raw meat off the ready-to-eat pile. Cool leftovers fast or eat them now. Party of 4 needs a bigger pot, not a shared half-cooked center.",
                    "Heat and separation prevent the usual field gut-punch.",
                    "Child gets fully cooked food, not the 'almost done' middle.",
                    "Stop if grease fire starts — lid, not water.",
                    "food-boil.png",
                    "Hierve. Separa crudo de listo. Enfría sobras o cómelas ya. Un grupo de 4 necesita olla grande.",
                    "El calor y la separación evitan el golpe de estómago.",
                    "El niño come lo bien cocido, no el centro 'casi'.",
                    "Si prende la grasa: tapa, no agua.",
                    party={"1": "1 pot, 1 meal.", "2": "Stagger boil so someone watches.", "4": "Two pots or two shifts; no shared half-raw meat."},
                )
            ],
        )
    )
    cards.append(
        card(
            "sig-mirror",
            "signaling",
            "Be found",
            "Que te encuentren",
            "You need a passing aircraft, a ridge party, or a road to notice you. No sat modem.",
            "Necesitas que un avión, un grupo en el filo o una carretera te vean. Sin módem satelital.",
            [
                ("You already have voice contact with your party.", "Ya tienes voz con tu grupo."),
                ("You are under a fire that signaling would spread — move first.", "Hay un fuego que la señal puede extender: muévete primero."),
            ],
            "Signaling is not a rescue guarantee. Still offer Emergency SOS if a cell net exists.",
            "Señalar no garantiza rescate. Aún así ofrece Emergency SOS si hay red.",
            [
                step(
                    "Three of anything: whistle, flash, ground X in contrasting cloth. Mirror toward sun and the target. Night: controlled torch, 3×, not a dead battery show.",
                    "Pattern beats random waving.",
                    "Child can blow the whistle on command, not play.",
                    "Stop wasting the battery if no one can possibly see you tonight — save SEARCH mode for a window.",
                    "signal-three.png",
                    "Tres de algo: silbato, destello, X en el suelo. Espejo al sol y al blanco. Noche: linterna 3×.",
                    "El patrón gana al meneo.",
                    "El niño sopla el silbato a la orden, no juega.",
                    "No gastes pila si nadie puede verte esta noche.",
                    party={"1": "You signal, you also stay put.", "2": "One signals, one watches the backtrail.", "4": "Signal / fire-tender / child-watch / runner only if the road is known."},
                )
            ],
        )
    )
    cards.append(
        card(
            "tact-formup",
            "tactics",
            "Form up",
            "Formar",
            "The party is strung out, a kid is not in sight, or the lead cannot see the tail.",
            "El grupo está estirado, un niño no se ve o el líder no ve la cola.",
            [
                ("Everyone is on the same rock and answered by name.", "Todos están en la misma roca y respondieron por nombre."),
                ("You are mid-crossing on a road or water — finish the crossing, then form.", "Estás a medio cruce: termínalo y luego forma."),
            ],
            "Lost-kid is not a Field browse problem. Comms lost-kid haptic + FORM UP. Then care if they are hurt.",
            "Niño perdido no es un browse de Field. Háptico lost-kid + FORMAR. Luego cuidado si está herido.",
            [
                step(
                    "Lead stops. Tail stops. Names out loud. Last pip + time. Do not have four people search four directions.",
                    "A moving search makes a second lost party.",
                    "The remaining children sit on packs with one adult, not in the search line.",
                    "Stop the fan-out if it is getting dark — stay, signal, wait.",
                    "form-up.png",
                    "El líder para. La cola para. Nombres en voz alta. Último pip y hora. No mandes a cuatro por cuatro rumbos.",
                    "Una búsqueda en movimiento crea un segundo grupo perdido.",
                    "Los demás niños se sientan con un adulto, no en la línea de búsqueda.",
                    "Si oscurece, quédense, señalen, esperen.",
                    tick_s=180,
                    party={"1": "You are the whole party — mark and stay.", "2": "One stays with kit, one walks back the last 100 m only.", "4": "Lead + tail freeze; one pair walks the last handrail only."},
                )
            ],
        )
    )
    # Additional core depth so categories are not single-card.
    cards.append(
        card(
            "med-airway",
            "medical",
            "Airway — they cannot breathe",
            "Vía aérea — no puede respirar",
            "Wheeze, swell, or silence after a sting, food, or smoke. They are still awake or just fading.",
            "Silibancia, hinchazón o silencio después de picadura, comida o humo.",
            [
                ("They are talking full sentences and the swelling is not growing.", "Habla frases completas y la hinchazón no crece."),
                ("They are unresponsive and not breathing — that is CPR, not this card.", "Sin respuesta y sin respirar: eso es RCP, no esta tarjeta."),
            ],
            "This is Emergency SOS territory. An auto-injector they already own is theirs to use; this app does not prescribe.",
            "Esto es territorio de Emergency SOS. Un autoinyector que ya sea suyo es de ellos; esta app no receta.",
            [
                step(
                    "Sit them up. Nothing in the mouth. If they have their own auto-injector and know it, they use it. Watch breathing.",
                    "Lying flat can worsen some swell. You are buying time.",
                    "Keep the child from offering water or candy.",
                    "If they stop breathing, leave this card for CPR.",
                    "airway.png",
                    "Siéntalos. Nada en la boca. Si tienen su autoinyector y lo conocen, lo usan. Vigila la respiración.",
                    "Tumbados puede empeorar. Estás comprando tiempo.",
                    "Que el niño no ofrezca agua ni dulce.",
                    "Si dejan de respirar, esta tarjeta se acaba: RCP.",
                    tick_s=60,
                )
            ],
        )
    )
    cards.append(
        card(
            "trauma-spine",
            "trauma",
            "They fell — do not twist",
            "Se cayó — no gires",
            "A fall, a roof, a cliff, or a car. Neck or back pain, numbness, or 'I heard a crack'.",
            "Una caída, un techo, un risco o un auto. Dolor de cuello o espalda, hormigueo o 'oí un crujido'.",
            [
                ("They already walked to you laughing with no pain — still watch, but this card is lighter.", "Ya caminó riendo sin dolor: vigila, la tarjeta pesa menos."),
                ("They are in a burning wreck — move them anyway, then this card is over.", "Están en un choque que arde: muévelos igual."),
            ],
            "Spine care is a hospital. You are preventing a second injury.",
            "La columna es del hospital. Tú evitas una segunda lesión.",
            [
                step(
                    "Hands on both sides of the head. Neutral. Log-roll only if vomit or water. Pad, do not sit them up for a photo.",
                    "Twisting a broken neck is how walking becomes not walking.",
                    "A child can hold the hand, not the head.",
                    "Stop pulling on a helmet unless the airway is dead.",
                    "spine.png",
                    "Manos a ambos lados de la cabeza. Neutro. Solo gira en bloque si hay vómito o agua.",
                    "Girar un cuello roto es cómo se deja de caminar.",
                    "El niño sostiene la mano, no la cabeza.",
                    "No quites el casco salvo que la vía esté muerta.",
                )
            ],
        )
    )
    return cards


def state_cards() -> list[dict]:
    return [
        card(
            "tx-cattle-guard",
            "nav",
            "Cattle guard",
            "Paso canadiense",
            "A steel grate across a ranch road. Ankle, bike, and dog hazard. Texas and New Mexico ranch edges.",
            "Rejilla de acero en un camino de rancho. Riesgo de tobillo, bici y perro.",
            [("You can walk around on firm ground.", "Puedes rodearlo por suelo firme.")],
            "Twisted ankle is still an evacuation if they cannot bear weight.",
            "Un tobillo torcido sigue siendo evacuación si no carga peso.",
            [
                step(
                    "Do not diagonal the grate. Step on the rails or walk the dirt bypass. Carry small dogs and small children.",
                    "A foot slides in and stays.",
                    "Hold the child's hand. They do not 'balance' across.",
                    "Stop if a cow panel is swinging — wait, do not climb it.",
                    "cattle-guard.png",
                    "No cruces en diagonal. Pisa los rieles o el bypass de tierra. Carga perros y niños chicos.",
                    "El pie se mete y se queda.",
                    "Toma la mano del niño. No 'equilibra'.",
                    "Si un panel de ganado se mueve, espera.",
                )
            ],
            states=["TX", "NM"],
        ),
        card(
            "tx-heat-island",
            "environment",
            "City heat island",
            "Isla de calor urbana",
            "Pavement, no shade, and a party still moving in an El Paso, Austin, or Albuquerque afternoon.",
            "Pavimento, sin sombra, y el grupo sigue en la tarde de El Paso, Austin o Albuquerque.",
            [("You have a cooled interior and water.", "Tienes un interior fresco y agua.")],
            "Same as heat collapse if they stop making sense.",
            "Igual que el colapso por calor si dejan de tener sentido.",
            [
                step(
                    "Cut the pace. Shade every 15 minutes. Water in, not just on. Watch the person in black kit.",
                    "Asphalt reradiates after the sun 'feels' done.",
                    "Stroller and kids get the shade first.",
                    "Stop the march if urine is dark and they are dizzy.",
                    "heat-island.png",
                    "Baja el ritmo. Sombra cada 15 minutos. Agua adentro, no solo encima.",
                    "El asfalto sigue radiando cuando el sol 'ya no pica'.",
                    "Coche y niños a la sombra primero.",
                    "Para si la orina está oscura y hay mareo.",
                    tick_s=900,
                )
            ],
            states=["TX"],
        ),
        card(
            "nm-monsoon",
            "environment",
            "Monsoon gully",
            "Cárcava de monzón",
            "New Mexico afternoon build-up. A dry wash can run while the sky over you is still blue.",
            "Tarde de monzón en Nuevo México. Un arroyo seco puede correr con el cielo aún azul.",
            [("You are already on a mesa with an exit that does not cross the wash.", "Ya estás en una mesa con salida que no cruza el arroyo.")],
            "A rolled vehicle or a drowned crossing is care you cannot give in the wash.",
            "Un cruce ahogado es cuidado que no puedes dar en el arroyo.",
            [
                step(
                    "Do not camp in the ditch. If thunder, leave the slot. Never drive a running dip. Wait — water drops as fast as it rose.",
                    "The flood is often from a cell you cannot see.",
                    "Kids do not 'play in the trickle' in a canyon bottom.",
                    "Stop if you hear a freight-train roar upstream.",
                    "monsoon.png",
                    "No acampes en la zanja. Si hay trueno, sal del slot. Nunca manejes un vado corriendo.",
                    "La crecida suele venir de una celda que no ves.",
                    "Los niños no juegan en el hilo de agua en el fondo.",
                    "Para si oyes un rugido de tren aguas arriba.",
                )
            ],
            states=["NM"],
        ),
        card(
            "nm-ice-rock",
            "environment",
            "Ice on rock",
            "Hielo en la roca",
            "Sandia or high NM rock with a film of ice. Any high ledge in a spring freeze reads the same.",
            "Roca alta de Sandia con una película de hielo. Cualquier cornisa alta en helada se lee igual.",
            [("You can walk a dry dirt bypass.", "Puedes ir por un bypass de tierra seca.")],
            "A sliding fall is trauma. Do not 'just try the slab'.",
            "Una caída al resbalar es trauma. No 'pruebes la losa'.",
            [
                step(
                    "Off the varnish. Microspikes if you have them. One at a time. Belay a child on a short leash of webbing, not a hand hold.",
                    "Thin ice on granite has no honest friction.",
                    "Child last, on the dry line, or turn around.",
                    "Stop the summit bid if the wind is loading more rime.",
                    "ice-rock.png",
                    "Fuera del barniz. Microspikes si hay. Uno por uno. El niño con cintas, no de la mano en el hielo.",
                    "El hielo fino en granito no tiene fricción honesta.",
                    "El niño al último, por lo seco, o den la vuelta.",
                    "Corten la cumbre si el viento carga más escarcha.",
                )
            ],
            states=["NM"],
        ),
        card(
            "tx-hurricane-paper",
            "environment",
            "Hurricane — procedure and paper",
            "Huracán — procedimiento y papel",
            "A named storm is in the story you already know. No live NWS in this app. You have a list and a paper map.",
            "Hay un huracán en la historia que ya conoces. Esta app no trae NWS en vivo. Tienes una lista y un mapa de papel.",
            [("You are already inland on a known floor above surge, with water and a radio you already own.", "Ya estás tierra adentro, sobre el oleaje, con agua y un radio que ya tienes.")],
            "This card is not a forecast. It is a leave / water / shutters / paper sequence.",
            "Esta tarjeta no es un pronóstico. Es una secuencia de salir / agua / persianas / papel.",
            [
                step(
                    "If you are still in a surge or flood polygon in the pack, leave on the printed route. Fill water. Paper copies of roster and MM / county roads. Tape does not beat a surge.",
                    "The app will not update the cone.",
                    "Child carries their own small bottle and shoes, not a toy.",
                    "Stop 'riding it out' on a barrier island because the map still looks pretty.",
                    "hurricane-paper.png",
                    "Si sigues en un polígono de oleaje, sal por la ruta impresa. Llena agua. Papel del roster y las millas.",
                    "La app no actualizará el cono.",
                    "El niño lleva su botella y zapatos, no un juguete.",
                    "No 'aguantes' en una isla de barrera porque el mapa se ve bonito.",
                )
            ],
            states=["TX"],
        ),
        card(
            "tx-nm-border-hospital",
            "medical",
            "Border hospitals",
            "Hospitales de la frontera",
            "El Paso / southern NM. Trauma may be on one side of a line you cannot see on a dirt road.",
            "El Paso / sur de NM. El trauma puede estar de un lado de una línea que no ves en un camino de tierra.",
            [("You already have a named hospital from the pack POI list.", "Ya tienes un hospital con nombre de la lista POI del pack.")],
            "Use the pack POIs for the next water and road.",
            "Esta tarjeta dice cómo usar los POI del pack.",
            [
                step(
                    "Search the pack for hospital / clinic. Note the name on paper. Do not assume the closest pin is the trauma center. If a net exists, Emergency SOS; if not, drive the marked road, not the wash.",
                    "A clinic pin is not a level-I trauma bay.",
                    "Child in the vehicle, not walking a fence.",
                    "Stop at a marked crossing. Do not cut a fence for a 'shortcut'.",
                    "border-hospital.png",
                    "Busca hospital/clínica en el pack. Anota el nombre. No asumas que el pin más cercano es trauma.",
                    "Una clínica no es un trauma nivel I.",
                    "Niño en el vehículo, no caminando la cerca.",
                    "Para en un cruce marcado. No cortes una cerca.",
                )
            ],
            states=["TX", "NM"],
        ),
    ]


def thickness_core() -> list[dict]:
    """Bleed/heat/water/lost/shelter/signal already live in core. Add fracture + cold."""
    return [
        card(
            "trauma-fracture",
            "trauma",
            "Closed fracture / bad angulation",
            "Fractura cerrada / mala angulación",
            "A limb is bent where it should not bend, or they cannot take weight after a fall. Skin is closed.",
            "Una extremidad está doblada donde no debe, o no carga peso después de una caída. La piel está cerrada.",
            [
                ("They can take weight and the limb looks like the other one.", "Puede cargar peso y la extremidad se ve como la otra."),
                ("Bone is out or the foot/hand is white and numb — this card is not enough.", "Hay hueso afuera o el pie/mano está blanco y entumecido: esta tarjeta no alcanza."),
            ],
            "Splint and carry to care. Emergency SOS if a net exists. Do not 'set' a bone because a video said so.",
            "Inmoviliza y lleva a cuidado. Emergency SOS si hay red. No 'aocomodes' un hueso por un video.",
            [
                step(
                    "Do not test the break. Pad and splint the joint above and the joint below. Tie loose enough that a fingertip fits. Check color of fingers or toes after.",
                    "Motion at the break makes bleeding and nerve damage worse.",
                    "A child holds the unused tape. They do not pull the limb straight.",
                    "Stop pulling if they scream through a pulse you can still feel — stabilize as-is and move.",
                    "fracture-splint.png",
                    "No pruebes la rotura. Almohadilla y férula la articulación de arriba y la de abajo. Que quepa un dedo. Revisa color de dedos.",
                    "Mover el quiebre empeora sangrado y nervios.",
                    "El niño sostiene la cinta. No estira la extremidad.",
                    "Para de tirar si grita con pulso que aún sientes: inmoviliza como está y mueve.",
                    party={"1": "Splint and walk them if they can.", "2": "One splints, one carries kit.", "4": "Splint / carry / trail / watch shock."},
                )
            ],
        ),
        card(
            "env-cold",
            "environment",
            "Cold and wet — stop the slide",
            "Frío y mojado — para la caída",
            "Shivering that will not quit, wet cotton, wind, or a party member who stopped complaining and just sits. No live NWS.",
            "Temblor que no para, algodón mojado, viento, o alguien que ya no se queja y se sienta. Sin NWS en vivo.",
            [
                ("They are dry, fed, and talking sense in a wind break.", "Están secos, comidos y hablan con sentido en un abrigo."),
                ("They are unconscious or not shivering in obvious cold — this is evacuation, not a snack.", "Están inconscientes o no tiemblan con frío obvio: es evacuación, no un snack."),
            ],
            "Rewarm trunk first. Get to care for confusion that does not clear.",
            "Recalienta el tronco primero. Busca cuidado si la confusión no pasa.",
            [
                step(
                    "Stop walking into wind. Change out of wet next-to-skin layers. Put the cold person in a bag or tarp with a warm body. Warm sweet drink only if they can swallow sitting up.",
                    "Wet cotton dumps heat. Walking harder in a cotton shirt makes it worse.",
                    "Child gets the dry layer first. No 'tough it out' races.",
                    "Stop oral fluids if they cannot sit or are vomiting. Do not put them in a cold creek to 'wake up'.",
                    "cold-rewarm.png",
                    "Para de caminar al viento. Cambia lo mojado pegado a la piel. Mételos en bolsa o lona con un cuerpo caliente. Bebida tibia solo si tragan sentados.",
                    "El algodón mojado tira el calor. Caminar más recio lo empeora.",
                    "El niño recibe la capa seca primero. Sin carreras de aguante.",
                    "Nada por boca si no se sientan o vomitan. No los metas a un arroyo frío para 'despertarlos'.",
                    tick_s=600,
                    party={"1": "Shelter and change.", "2": "One shelters, one fetches dry/kit.", "4": "Shelter / dry / stove / watch the rest."},
                )
            ],
        ),
        card(
            "plant-use",
            "plants",
            "Trees and brush — use, don't eat",
            "Árboles y matorral — úsalos, no los comas",
            "You are in tree cover, bosque, or a park. Shade, wind, and deadfall are the uses. This is not a meal.",
            "Estás en arbolado, bosque o parque. Sombra, viento y madera muerta. Esto no es una comida.",
            [
                ("You already have known food and a roof.", "Ya tienes comida conocida y techo."),
                ("Lips, tongue, or skin are already burning — that is a medical card, not a use card.", "Labios, lengua o piel ya arden: eso es médico, no uso."),
            ],
            "Vision is a guess. Nothing in this app unlocks a meal. If they chewed bark or seed, get to care for vomiting, trouble breathing, or collapse.",
            "Vision es una conjetura. Nada aquí desbloquea una comida. Si masticaron corteza o semilla, busca cuidado.",
            [
                step(
                    "Use the trees: shade on the south side, wind break, deadfall only for fire. Do not strip live bark. Do not chew seeds, pods, or pretty flowers. Wash sap off skin.",
                    "A tree is calories only after a name you already trust. Shade is the honest use today.",
                    "Take the leaf or pod out of a child's hand. No tiny taste.",
                    "Stop if anyone's mouth tingles or a rash starts — sit, watch airway, offer Emergency SOS if a net exists.",
                    "plant-use.png",
                    "Úsalos: sombra al sur, cortaviento, madera muerta para fuego. No descortezces vivo. No mastiques semillas ni flores.",
                    "Un árbol es caloría solo con un nombre que ya confías. Hoy la sombra es el uso honesto.",
                    "Saca la hoja o vaina de la mano del niño. Sin probadita.",
                    "Para si hormiguea la boca o sale sarpullido: sienta, vigila vía aérea, ofrece Emergency SOS si hay red.",
                    party={"1": "Shade and sit.", "2": "One makes shade, one fetches deadfall.", "4": "Shade / fire / water / watch the rest."},
                )
            ],
        ),
        card(
            "cave-dark",
            "environment",
            "Cave or hole — do not go in alone",
            "Cueva o hueco — no entres solo",
            "A hole, sink, or cave mouth is in the record. Air, dark, and cold. Not a tour.",
            "Hay un hueco, dolina o boca de cueva en el registro. Aire, oscuridad y frío. No es un tour.",
            [
                ("You can stay in daylight and the party knows where you are.", "Puedes quedarte a la luz y el grupo sabe dónde estás."),
                ("Someone is already inside and not answering — that is search, not this card.", "Alguien ya está adentro y no responde: eso es búsqueda, no esta tarjeta."),
            ],
            "Hypothermia and bad air are the field facts. A fall in the dark is trauma. Get to care for confusion, a fall, or anyone who will not wake.",
            "Hipotermia y mal aire son los hechos. Una caída en la oscuridad es trauma. Busca cuidado si hay confusión, una caída o alguien que no despierta.",
            [
                step(
                    "A hole, sink, or cave mouth. Dark, still air, cold. Do not go in alone. Stay in daylight unless the party knows you are going in and one person stays out. Light in hand before the mouth. Feel the air — if a flame dies or you get a headache, back out. Do not chimney a sinkhole.",
                    "Caves kill by cold, air, and a step you cannot see. A phone light is not a plan.",
                    "A child does not go in. They sit with the person who stays out.",
                    "Stop at the mouth if you cannot see the floor, if water is running, or if anyone is already cold.",
                    "cave-dark.png",
                    "Un hueco, dolina o boca de cueva. Oscuridad, aire quieto, frío. No entres solo. Quédate a la luz salvo que el grupo sepa que entras y uno se quede fuera. Luz en la mano. Si una llama muere o duele la cabeza, sal. No te metas a una dolina.",
                    "Las cuevas matan por frío, aire y un paso que no ves. La linterna del teléfono no es un plan.",
                    "El niño no entra. Se sienta con quien se queda fuera.",
                    "Para en la boca si no ves el piso, si corre agua o si alguien ya tiene frío.",
                    party={"1": "Stay out. Mark the mouth.", "2": "One in sight of daylight, one outside.", "4": "One in / one at mouth / one with kit / one on watch."},
                )
            ],
        ),
        card(
            "food-game",
            "food",
            "Meat you already have",
            "Carne que ya tienes",
            "You have an animal you already took, or someone handed you meat. This is not a hunting map and it does not know where animals are.",
            "Tienes un animal que ya cazaste, o te pasaron carne. Esto no es un mapa de caza y no sabe dónde están los animales.",
            [
                ("The meat is commercially sealed and undamaged.", "La carne es comercial, sellada e intacta."),
                ("You did not see it die, it smells like death, or flies have had it — leave it.", "No lo viste morir, huele a muerte o ya lo tuvieron las moscas: déjalo."),
            ],
            "Gut illness is care if they cannot keep fluids down. This card does not ID a species and does not unlock a kill.",
            "El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no identifica especie ni desbloquea una caza.",
            [
                step(
                    "If you did not see it die, leave it. If you did: keep it cool, gut away from water and camp, cook until the juice runs clear. No raw. Hands and knives washed after.",
                    "Mystery meat is how camps get sick. Heat and distance from the creek are the field rules.",
                    "Child gets fully cooked food, not the 'almost done' middle, and does not help gut.",
                    "Stop if grease fire starts — lid, not water. Stop if the meat smells like death.",
                    "food-game.png",
                    "Si no lo viste morir, déjalo. Si sí: frío, vísceras lejos del agua y del campamento, cocina hasta que el jugo salga claro. Nada crudo.",
                    "La carne misteriosa enferma al campamento. Calor y distancia del arroyo son las reglas.",
                    "El niño come lo bien cocido, no el centro 'casi', y no ayuda a eviscerar.",
                    "Si prende la grasa: tapa, no agua. Para si huele a muerte.",
                    party={"1": "Cook through or leave it.", "2": "One guts away from camp, one watches the pot.", "4": "Gut / cook / water / keep animals and kids off the pile."},
                )
            ],
        ),
    ]


def plant_danger_do_en(cid: str) -> str:
    if cid.startswith("nm-"):
        return (
            "Datura. Pretty is not food. Do not taste it to 'check'. "
            "Brush off, then water on skin and eyes. "
            "Do not make a tea or a poultice. Photograph the plant only if you are already clear of sap."
        )
    return (
        "Oleander or Texas mountain laurel. Pretty is not food. Do not taste it to 'check'. "
        "Brush off, then water on skin and eyes. Do not make a tea or a poultice. "
        "Photograph the plant only if you are already clear of sap."
    )


def plant_danger_do_es(cid: str) -> str:
    if cid.startswith("nm-"):
        return (
            "Datura. Lo bonito no es comida. No lo pruebes para 'ver'. "
            "Sacude, luego agua en piel y ojos. "
            "No hagas té ni emplasto."
        )
    return (
        "Adelfa o Texas mountain laurel. Lo bonito no es comida. No lo pruebes para 'ver'. "
        "Sacude, luego agua en piel y ojos. No hagas té ni emplasto."
    )


def tree_do_en(cid: str) -> str:
    if cid == "tx-east-tree-use":
        return (
            "Live oak, pecan, cedar elm, loblolly pine, cottonwood. "
            "Loblolly pine is Lost Pines. "
            "South-side shade, wind break, deadfall only for fire. "
            "Do not strip live bark. Do not chew seeds, pods, or pretty flowers. Wash sap off skin."
        )
    if cid.startswith("tx-"):
        return (
            "Live oak, pecan, mesquite, cedar elm, cottonwood. "
            "Mesquite is woodland. "
            "South-side shade, wind break, deadfall only for fire. "
            "Do not strip live bark. Do not chew seeds, pods, or pretty flowers. Wash sap off skin."
        )
    return (
        "Rio Grande cottonwood, juniper, piñon. Juniper and piñon are woodland. Aspen is high country. "
        "South-side shade, wind break, deadfall only for fire. "
        "Do not strip live bark. Do not chew seeds, pods, or pretty flowers. Wash sap off skin."
    )


def tree_do_es(cid: str) -> str:
    if cid == "tx-east-tree-use":
        return (
            "Encino, pecán, olmo cedro, pino taeda, álamo. "
            "El pino taeda es de Lost Pines. "
            "Sombra al sur, cortaviento, madera muerta para fuego. "
            "No descortezces vivo. No mastiques semillas ni flores."
        )
    if cid.startswith("tx-"):
        return (
            "Encino, pecán, mezquite, olmo cedro, álamo. "
            "El mezquite es de arbolado. "
            "Sombra al sur, cortaviento, madera muerta para fuego. "
            "No descortezces vivo. No mastiques semillas ni flores."
        )
    return (
        "Álamo del Río Grande, enebro, piñón. El enebro y el piñón son de arbolado. El álamo temblón es de alta montaña. "
        "Sombra al sur, cortaviento, madera muerta para fuego. "
        "No descortezces vivo. No mastiques semillas ni flores."
    )


def cactus_do_en(cid: str) -> str:
    if cid.startswith("nm-"):
        return (
            "Cholla, yucca, sotol. Give it room. Comb joints and glochids out with a comb or tape, not fingers. "
            "Do not chew pads, fruit, or flower. Wash sap off skin and eyes with water."
        )
    return (
        "Prickly pear and yucca. Give it room. Comb glochids out with a comb or tape, not fingers. "
        "Do not chew pads, fruit, or flower. Wash sap off skin and eyes with water."
    )


def cactus_do_es(cid: str) -> str:
    if cid.startswith("nm-"):
        return (
            "Cholla, yuca, sotol. Da espacio. Peina segmentos y globidios con peine o cinta, no con los dedos. "
            "No mastiques nopales, fruto ni flor. Lava savia con agua."
        )
    return (
        "Nopal y yuca. Da espacio. Peina globidios con peine o cinta, no con los dedos. "
        "No mastiques nopales, fruto ni flor. Lava savia con agua."
    )


def game_do_en(cid: str) -> str:
    if cid == "tx-east-game":
        lead = "Feral hog or white-tailed deer you already have. "
    elif cid.startswith("tx-"):
        lead = "Javelina or white-tailed deer you already have. "
    else:
        lead = "Elk or mule deer you already have. "
    return (
        lead
        + "If you did not see it die, leave it. If you did: keep it cool, gut away from water and camp, "
        "cook until the juice runs clear. No raw. Hands and knives washed after. Do not hunt from this map."
    )


def game_do_es(cid: str) -> str:
    if cid == "tx-east-game":
        lead = "Cerdo asilvestrado o venado cola blanca que ya tienes. "
    elif cid.startswith("tx-"):
        lead = "Pecarí o venado cola blanca que ya tienes. "
    else:
        lead = "Wapití o venado bura que ya tienes. "
    return (
        lead
        + "Si no lo viste morir, déjalo. Si sí: frío, vísceras lejos del agua y del campamento, "
        "cocina hasta que el jugo salga claro. Nada crudo. No caces desde este mapa."
    )


def snake_do_en(cid: str) -> str:
    if cid == "tx-east-snake":
        lead = "Copperhead or cottonmouth. "
    elif cid.startswith("tx-"):
        lead = "Western diamondback. "
    else:
        lead = "Prairie rattler or diamondback. "
    return (
        lead
        + "Back away the way you came. Do not kill or bag the snake. If bitten: sit, still the limb at heart level, "
        "walk to a road if you can. Note time. No ice, no cut, no suck, no tourniquet."
    )


def snake_do_es(cid: str) -> str:
    if cid == "tx-east-snake":
        lead = "Cabeza de cobre o boca de algodón. "
    elif cid.startswith("tx-"):
        lead = "Cascabel del oeste. "
    else:
        lead = "Cascabel de pradera o del oeste. "
    return (
        lead
        + "Retrocede por donde viniste. No mates ni embolses la culebra. Si hay mordida: sienta, "
        "extremidad quieta al corazón, camina a un camino si puedes. Anota la hora."
    )


def mammal_do_en(cid: str) -> str:
    if cid == "tx-east-mammal":
        return (
            "Feral hog charges when cornered — give it the brush, do not get between it and cover. "
            "Coyote: do not feed. White-tailed deer at dusk — give it the road. "
            "Food away from camp. If bitten, the bite card. If you already have meat, "
            "the food card. Do not hunt from this map."
        )
    if cid.startswith("tx-"):
        return (
            "Javelina charges when cornered — give it the brush, do not get between it and cover. "
            "Coyote: do not feed. White-tailed deer at dusk — give it the road. "
            "Food away from camp. If bitten, the bite card. "
            "If you already have meat, the food card. Do not hunt from this map."
        )
    return (
        "Black bear: do not run, stand large, food sealed and away from camp. "
        "Elk is high country. Elk in rut: give way. Mule deer at dusk — give it the road. A maul is trauma. "
        "If bitten, the bite card. If you already have meat, the food card. "
        "Do not hunt from this map."
    )


def mammal_do_es(cid: str) -> str:
    if cid == "tx-east-mammal":
        return (
            "El cerdo asilvestrado embiste si lo acorralas: déjale el matorral, no te pongas entre él y la cubierta. "
            "Coyote: no alimentes. Venado cola blanca al anochecer — cede el camino. "
            "Comida lejos del campamento. Si hay mordida, la tarjeta de mordedura. "
            "Si ya tienes carne, la de comida. No caces desde este mapa."
        )
    if cid.startswith("tx-"):
        return (
            "El pecarí embiste si lo acorralas: déjale el matorral, no te pongas entre él y la cubierta. "
            "Coyote: no alimentes. Venado cola blanca al anochecer — cede el camino. "
            "Comida lejos del campamento. Si hay mordida, la tarjeta de mordedura. "
            "Si ya tienes carne, la de comida. No caces desde este mapa."
        )
    return (
        "Oso negro: no corras, hazte grande, comida sellada y lejos del campamento. "
        "El wapití es de alta montaña. Wapití en celo: cede el paso. Venado bura al anochecer — cede el camino. "
        "Un golpe es trauma. Si hay mordida, la tarjeta de mordedura. "
        "Si ya tienes carne, la tarjeta de comida. No caces desde este mapa."
    )


def thickness_state() -> list[dict]:
    """Snake and plant-danger of that state. No cross-coast leak. No edible unlock."""
    snakes = [
        (
            "tx-snake",
            ["TX"],
            "West Texas pit viper",
            "Víbora del oeste de Texas",
            "West Texas brush, desert, or open reserve. Western diamondback country. Do not catch it for a photo ID.",
            "Matorral, desierto o reserva abierta del oeste de Texas. Cascabel del oeste. No la atrapes para identificarla.",
            "Western diamondback: keep the bitten limb still at heart level. No ice, no cut, no suck, no tourniquet.",
            "Cascabel del oeste: extremidad quieta a la altura del corazón. Sin hielo, sin cortar, sin chupar, sin torniquete.",
        ),
        (
            "tx-east-snake",
            ["TX"],
            "East Texas pit viper",
            "Víbora del este de Texas",
            "East Texas brush, bosque, or wetland. Copperhead or cottonmouth country. Do not catch it for a photo ID.",
            "Matorral, bosque o humedal del este de Texas. Cabeza de cobre o boca de algodón. No la atrapes para identificarla.",
            "Copperhead or cottonmouth: keep the bitten limb still at heart level. No ice, no cut, no suck, no tourniquet.",
            "Cabeza de cobre o boca de algodón: extremidad quieta a la altura del corazón. Sin hielo, sin cortar, sin chupar, sin torniquete.",
        ),
        (
            "nm-snake",
            ["NM"],
            "New Mexico rattlesnake",
            "Cascabel de Nuevo México",
            "New Mexico brush, desert, or open reserve. Prairie rattler or western diamondback country. Do not pin it with a stick.",
            "Matorral, desierto o reserva abierta de Nuevo México. Cascabel de pradera o del oeste. No la claves con un palo.",
            "Same US pit-viper rule: still limb, walk out if you can, Emergency SOS if a net exists.",
            "Misma regla de víbora de foseta: extremidad quieta, camina si puedes, Emergency SOS si hay red.",
        ),
    ]
    plants = [
        (
            "tx-plant-danger",
            ["TX"],
            "Texas plant danger — do not chew",
            "Planta peligrosa de Texas — no mastiques",
            "Oleander hedge or Texas mountain laurel seed. Pretty is not food.",
            "Seto de adelfa o semilla de Texas mountain laurel. Lo bonito no es comida.",
            "Oleander and mountain laurel seeds can stop a heart. Do not make tea. Wash sap off skin and eyes with water.",
            "Adelfa y las semillas pueden parar un corazón. No hagas té. Lava savia de piel y ojos con agua.",
        ),
        (
            "nm-plant-danger",
            ["NM"],
            "New Mexico plant danger — do not chew",
            "Planta peligrosa de Nuevo México — no mastiques",
            "Sacred datura trumpet. Pretty is not food.",
            "Trompeta de datura. Lo bonito no es comida.",
            "Datura is a poison, not a medicine card. Do not make tea. Wash sap off skin and eyes with water.",
            "La datura es veneno, no una tarjeta de medicina. No hagas té. Lava savia de piel y ojos con agua.",
        ),
    ]
    out = []
    for cid, states, title, title_es, sit, sit_es, care, care_es in snakes:
        out.append(
            card(
                cid,
                "animals",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("The snake is gone and no one was bitten.", "La culebra se fue y nadie fue mordido."),
                    ("They are bitten and already not breathing — go to airway / CPR, then this card is secondary.", "Hay mordida y ya no respiran: vía aérea / RCP, esta tarjeta es secundaria."),
                ],
                care,
                care_es,
                [
                    step(
                        snake_do_en(cid),
                        "US pit vipers are not treated with jungle-movie first aid. Time to a hospital is the treatment.",
                        "Child stays behind the adult. No stick-poking.",
                        "Stop chasing the snake for 'ID'. A phone photo from far is enough if it is safe.",
                        f"{cid}.png",
                        snake_do_es(cid),
                        "Las víboras de foseta de EE. UU. no se tratan como en las películas. El tiempo al hospital es el tratamiento.",
                        "El niño detrás del adulto. Sin pinchar con palo.",
                        "No persigas la culebra para 'identificarla'. Una foto de lejos basta si es seguro.",
                        party={"1": "Sit, still limb, walk out.", "2": "One stays with the bitten, one finds the road.", "4": "Patient / still limb / navigation / SOS offer if a net exists."},
                    )
                ],
                states=states,
                packs=packs_for(cid),
            )
        )
    for cid, states, title, title_es, sit, sit_es, care, care_es in plants:
        out.append(
            card(
                cid,
                "plants",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("Nobody put it in a mouth and sap is off skin.", "Nadie se lo metió a la boca y la savia está fuera de la piel."),
                    ("They swallowed a seed or sap is in both eyes and they cannot see — this is care now.", "Tragó una semilla o hay savia en los dos ojos y no ve: esto es cuidado ahora."),
                ],
                care,
                care_es,
                [
                    step(
                        plant_danger_do_en(cid),
                        "A pretty flower is not a calorie.",
                        "Child does not carry the pretty seed as a toy.",
                        "Stop if they start vomiting or see halos — sit, watch airway, offer Emergency SOS if a net exists.",
                        f"{cid}.png",
                        plant_danger_do_es(cid),
                        "Una flor bonita no es una caloría.",
                        "El niño no lleva la semilla bonita de juguete.",
                        "Para si vomita o ve halos: sienta, vigila vía aérea, ofrece Emergency SOS si hay red.",
                    )
                ],
                states=states,
                packs=packs_for(cid),
                speak=True,
            )
        )
    trees = [
        (
            "tx-tree-use",
            ["TX"],
            "West Texas trees — shade, not a meal",
            "Árboles del oeste de Texas — sombra, no comida",
            "You are in West Texas woodland, park, or bosque. Live oak, pecan, cedar elm, cottonwood. Mesquite is woodland. Shade, thorns, deadfall.",
            "Estás en arbolado, parque o bosque del oeste de Texas. Encino, pecán, olmo cedro, álamo. El mezquite es de arbolado. Sombra, espinas, madera muerta.",
            "If they chewed seed or sap is in both eyes, this is care now, not a use card.",
            "Si masticaron semilla o hay savia en los ojos, esto es cuidado ahora, no una tarjeta de uso.",
        ),
        (
            "nm-tree-use",
            ["NM"],
            "New Mexico trees — shade, not a meal",
            "Árboles de Nuevo México — sombra, no comida",
            "You are in New Mexico woodland, park, or bosque. Rio Grande cottonwood, juniper, piñon. Aspen is high country. Shade and wind. Piñon is not a Field meal ticket.",
            "Estás en arbolado, parque o bosque de Nuevo México. Álamo del Río Grande, enebro, piñón. El álamo temblón es de alta montaña. Sombra y viento. El piñón no es un ticket de comida de Field.",
            "If they chewed seed or sap is in both eyes, this is care now.",
            "Si masticaron semilla o hay savia en los ojos, esto es cuidado ahora.",
        ),
        (
            "tx-east-tree-use",
            ["TX"],
            "East Texas trees — shade, not a meal",
            "Árboles del este de Texas — sombra, no comida",
            "You are in East Texas woodland, park, bosque, or Lost Pines. Live oak, pecan, cedar elm, loblolly pine, cottonwood. Shade and deadfall.",
            "Estás en arbolado, parque, bosque o Lost Pines del este de Texas. Encino, pecán, olmo cedro, pino taeda, álamo. Sombra y madera muerta.",
            "If they chewed seed or sap is in both eyes, this is care now, not a use card.",
            "Si masticaron semilla o hay savia en los ojos, esto es cuidado ahora, no una tarjeta de uso.",
        ),
    ]
    for cid, states, title, title_es, sit, sit_es, care, care_es in trees:
        out.append(
            card(
                cid,
                "plants",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("You already have shade and known food.", "Ya tienes sombra y comida conocida."),
                    ("Lips, tongue, or skin are already burning — that is a medical card, not a use card.", "Labios, lengua o piel ya arden: eso es médico, no uso."),
                ],
                care,
                care_es,
                [
                    step(
                        tree_do_en(cid),
                        "A named tree is calories only after a name you already trust. Shade is the honest use today.",
                        "Take the leaf or pod out of a child's hand. No tiny taste.",
                        "Stop if anyone's mouth tingles or a rash starts — sit, watch airway, offer Emergency SOS if a net exists.",
                        f"{cid}.png",
                        tree_do_es(cid),
                        "Un árbol es caloría solo con un nombre que ya confías. Hoy la sombra es el uso honesto.",
                        "Saca la hoja o vaina de la mano del niño. Sin probadita.",
                        "Para si hormiguea la boca o sale sarpullido: sienta, vigila vía aérea, ofrece Emergency SOS si hay red.",
                        party={"1": "Shade and sit.", "2": "One makes shade, one fetches deadfall.", "4": "Shade / fire / water / watch the rest."},
                    )
                ],
                states=states,
                packs=packs_for(cid),
                speak=True,
            )
        )
    mammals = [
        (
            "tx-mammal",
            ["TX"],
            "West Texas mammals — give space",
            "Mamíferos del oeste de Texas — da espacio",
            "Javelina, coyote, white-tailed deer country. This is range, not a pin. The map does not know where one is standing.",
            "País de pecarí, coyote y venado cola blanca. Esto es rango, no un pin. El mapa no sabe dónde está uno.",
            "A puncture or a maul is trauma. Gut illness is care if they cannot keep fluids down. This card does not unlock a hunt.",
            "Una herida o un golpe es trauma. El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no desbloquea una caza.",
        ),
        (
            "tx-east-mammal",
            ["TX"],
            "East Texas mammals — give space",
            "Mamíferos del este de Texas — da espacio",
            "Coyote, white-tailed deer, and feral hog country. This is range, not a pin. The map does not know where one is standing.",
            "País de coyote, venado cola blanca y cerdo asilvestrado. Esto es rango, no un pin. El mapa no sabe dónde está uno.",
            "A puncture or a maul is trauma. Gut illness is care if they cannot keep fluids down. This card does not unlock a hunt.",
            "Una herida o un golpe es trauma. El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no desbloquea una caza.",
        ),
        (
            "nm-mammal",
            ["NM"],
            "New Mexico mammals — give space",
            "Mamíferos de Nuevo México — da espacio",
            "Black bear and mule deer country. Elk is high country. This is range, not a pin. Food storage, not photos.",
            "País de oso negro y venado bura. El wapití es de alta montaña. Esto es rango, no un pin. Guarda comida, no fotos.",
            "A maul is trauma. Don't run from a black bear. This card does not unlock a hunt.",
            "Un golpe es trauma. No corras de un oso negro. Esta tarjeta no desbloquea una caza.",
        ),
    ]
    for cid, states, title, title_es, sit, sit_es, care, care_es in mammals:
        out.append(
            card(
                cid,
                "animals",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("The animal is gone and no one is hurt.", "El animal se fue y nadie está herido."),
                    ("They are bleeding or cannot breathe — that is trauma / airway, then this card is secondary.", "Hay sangrado o no respiran: trauma / vía aérea, esta tarjeta es secundaria."),
                ],
                care,
                care_es,
                [
                    step(
                        mammal_do_en(cid),
                        "Range is the Field book of the open pack. A coordinate is not an animal.",
                        "A child stays behind the adult. No chasing for a photo.",
                        "Stop if it charges or if anyone is down — trauma card, then this one.",
                        f"{cid}.png",
                        mammal_do_es(cid),
                        "El rango es el libro de Field del paquete abierto. Una coordenada no es un animal.",
                        "El niño detrás del adulto. Sin perseguir para una foto.",
                        "Para si embiste o si alguien está en el suelo: tarjeta de trauma, luego esta.",
                        party={"1": "Give space. Sit.", "2": "One watches the animal, one moves the party.", "4": "Watch / move kids / food / rear guard."},
                    )
                ],
                states=states,
                packs=packs_for(cid),
            )
        )
    cactus = [
        (
            "tx-cactus",
            ["TX"],
            "Texas cactus and yucca — spines, not a meal",
            "Cactus y yuca de Texas — espinas, no comida",
            "Prickly pear and yucca country. Glochids and sharp tips. Vision does not unlock pads.",
            "País de nopal y yuca. Globidios y puntas. Vision no desbloquea nopales.",
            "Glochids and sap in the eye are care. This card does not unlock a meal.",
            "Globidios y savia en el ojo son cuidado. Esta tarjeta no desbloquea una comida.",
        ),
        (
            "nm-cactus",
            ["NM"],
            "New Mexico cactus and yucca — spines, not a meal",
            "Cactus y yuca de Nuevo México — espinas, no comida",
            "Cholla, yucca, sotol. Joints hitchhike on skin. Do not chew the flower.",
            "Cholla, yuca, sotol. Los segmentos se pegan a la piel. No comas la flor.",
            "A joint in the skin is comb, not squeeze. Sap in the eye is care.",
            "Un segmento en la piel se peina, no se aprieta. Savia en el ojo es cuidado.",
        ),
    ]
    for cid, states, title, title_es, sit, sit_es, care, care_es in cactus:
        out.append(
            card(
                cid,
                "plants",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("Spines are off skin and nobody put a pad in a mouth.", "Las espinas están fuera de la piel y nadie se metió un nopal a la boca."),
                    ("Sap is in both eyes or they chewed it — this is care now.", "Hay savia en los dos ojos o lo masticaron: esto es cuidado ahora."),
                ],
                care,
                care_es,
                [
                    step(
                        cactus_do_en(cid),
                        "Spines are the honest use of this plant today: stay clear. A pad is not a Field meal.",
                        "A child does not carry a joint or a pretty flower.",
                        "Stop if anyone's mouth tingles or an eye swells — sit, water on the eye, offer Emergency SOS if a net exists.",
                        f"{cid}.png",
                        cactus_do_es(cid),
                        "Hoy las espinas son el uso honesto: apártate. Un nopal no es una comida de Field.",
                        "El niño no lleva un segmento ni una flor bonita.",
                        "Para si hormiguea la boca o hincha un ojo: sienta, agua en el ojo, ofrece Emergency SOS si hay red.",
                    )
                ],
                states=states,
                packs=packs_for(cid),
                speak=True,
            )
        )
    game = [
        (
            "tx-game",
            ["TX"],
            "Javelina or deer you already have",
            "Pecarí o venado que ya tienes",
            "You have a javelina or white-tailed deer you already took, or someone handed you the meat. This is not a hunting map.",
            "Tienes pecarí o venado cola blanca que ya cazaste, o te pasaron la carne. Esto no es un mapa de caza.",
            "Gut illness is care if they cannot keep fluids down. This card does not unlock a kill.",
            "El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no desbloquea una caza.",
        ),
        (
            "tx-east-game",
            ["TX"],
            "Hog or deer you already have",
            "Cerdo o venado que ya tienes",
            "You have a feral hog or white-tailed deer you already took, or someone handed you the meat. This is not a hunting map.",
            "Tienes cerdo asilvestrado o venado cola blanca que ya cazaste, o te pasaron la carne. Esto no es un mapa de caza.",
            "Gut illness is care if they cannot keep fluids down. This card does not unlock a kill.",
            "El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no desbloquea una caza.",
        ),
        (
            "nm-game",
            ["NM"],
            "Elk or mule deer you already have",
            "Wapití o venado bura que ya tienes",
            "You have elk or mule deer you already took, or someone handed you the meat. This is not a hunting map.",
            "Tienes wapití o venado bura que ya cazaste, o te pasaron la carne. Esto no es un mapa de caza.",
            "Gut illness is care if they cannot keep fluids down. This card does not unlock a kill.",
            "El mal de estómago va a cuidado si no retienen líquidos. Esta tarjeta no desbloquea una caza.",
        ),
    ]
    for cid, states, title, title_es, sit, sit_es, care, care_es in game:
        out.append(
            card(
                cid,
                "food",
                title,
                title_es,
                sit,
                sit_es,
                [
                    ("The meat is commercially sealed and undamaged.", "La carne es comercial, sellada e intacta."),
                    ("You did not see it die, it smells like death, or flies have had it — leave it.", "No lo viste morir, huele a muerte o ya lo tuvieron las moscas: déjalo."),
                ],
                care,
                care_es,
                [
                    step(
                        game_do_en(cid),
                        "Mystery meat is how camps get sick. Heat and distance from the creek are the field rules.",
                        "Child gets fully cooked food, not the 'almost done' middle, and does not help gut.",
                        "Stop if grease fire starts — lid, not water. Stop if the meat smells like death.",
                        f"{cid}.png",
                        game_do_es(cid),
                        "La carne misteriosa enferma al campamento. Calor y distancia del arroyo son las reglas.",
                        "El niño come lo bien cocido, no el centro 'casi', y no ayuda a eviscerar.",
                        "Si prende la grasa: tapa, no agua. Para si huele a muerte.",
                        party={"1": "Cook through or leave it.", "2": "One guts away from camp, one watches the pot.", "4": "Gut / cook / water / keep animals and kids off the pile."},
                    )
                ],
                states=states,
                packs=packs_for(cid),
            )
        )
    return out


def from_nothing_core() -> list[dict]:
    """Long-term living with what you have. Not a hunt, not a meal unlock."""
    return [
        card(
            "camp-start",
            "tactics",
            "Starting from nothing",
            "Empezar desde nada",
            "Clothes, this pack, and the party. No kit is promised. Night, heat, or thirst is already working.",
            "Ropa, este pack y el grupo. No hay kit prometido. Ya trabajan la noche, el calor o la sed.",
            [
                ("Someone is already dying — open the medical card that names it, not this order.", "Alguien ya se está muriendo: abre la tarjeta médica, no este orden."),
                ("Water is rising in the cut — get out. This card is not a flood card.", "El agua sube en la quebrada: sal. Esta no es la tarjeta de creciente."),
            ],
            "This is order of work, not a rescue. Confusion, no urine, or a person who will not wake is care.",
            "Esto es orden de trabajo, no un rescate. Confusión, no orinar o alguien que no despierta es cuidado.",
            [
                step(
                    "STOP. Count the party. Shade or a windbreak before a walk. Do not eat a plant you cannot name. Do not split past voice.",
                    "Motion feels like a plan. Shade and a headcount are the plan.",
                    "Give the child a sit-job: count people, hold the whistle, stay on the pack.",
                    "Stop walking if two people have two different 'I'm sure' directions.",
                    "form-up.png",
                    "PARA. Cuenta al grupo. Sombra o cortaviento antes de caminar. No comas una planta que no puedes nombrar. No se separen más allá de la voz.",
                    "Moverse parece un plan. La sombra y el recuento son el plan.",
                    "El niño se sienta: cuenta gente, sostiene el silbato, se queda en la mochila.",
                    "No caminen si dos personas tienen dos 'estoy seguro' distintos.",
                    tick_s=180,
                    party={"1": "Shade, sit, think.", "2": "One makes shade, one counts kit.", "4": "Shade / water scout / fire / watch."},
                ),
                step(
                    "Water next, then fire, then a roof, then a signal a passer can see. Food is last, and only what you already trust.",
                    "Calories keep. Thirst, cold, and being invisible kill first.",
                    "Child drinks treated water and sits in the shade. They do not taste plants 'to help'.",
                    "Stop the forage if anyone's mouth tingles. Open the unknown-plant card.",
                    "form-up.png",
                    "Agua después, luego fuego, luego techo, luego una señal que un transeúnte vea. La comida es lo último, y solo lo que ya confías.",
                    "La caloría espera. La sed, el frío y no ser visto matan primero.",
                    "El niño bebe agua tratada y se sienta a la sombra. No prueba plantas 'para ayudar'.",
                    "Para el forrajeo si hormiguea la boca. Abre la tarjeta de planta desconocida.",
                    party={"1": "Water, then spark, then roof.", "2": "One water, one fire.", "4": "Water / fire / roof / signal."},
                ),
                step(
                    "Stay put if anyone is looking. Walk only a handrail you can name — a road, a river you can see, a ridge. Not a wash at night.",
                    "Lost people loop. A named line is how you meet a road without dying in a cut.",
                    "Child stays on the rope or the adult's belt, not as scout.",
                    "Stop and get high if you hear water in the cut or the sky goes black-green.",
                    "nav-stop.png",
                    "Quédate si alguien te busca. Camina solo una baranda que puedas nombrar: camino, río que ves, filo. No un arroyo de noche.",
                    "Los perdidos dan vueltas. Una línea con nombre es cómo llegas a un camino sin morir en una quebrada.",
                    "El niño va del cordón o del cinturón, no de explorador.",
                    "Para y sube si oyes agua en la quebrada o el cielo se pone negro-verde.",
                ),
            ],
        ),
        card(
            "water-find",
            "water",
            "Find water before you treat it",
            "Encuentra agua antes de tratarla",
            "Mouth is dry. You need a source. No lab, no live spring map.",
            "La boca está seca. Necesitas una fuente. Sin laboratorio ni mapa de manantiales en vivo.",
            [
                ("You have sealed commercial water.", "Tienes agua comercial sellada."),
                ("The only pool has a chemical sheen, a carcass, or a sewage smell — walk farther.", "El único charco tiene irisado, un cadáver o olor a cloaca: camina más."),
            ],
            "Finding water is not disinfection. Open Make water less bad next. Care for no urine, bloody stool, or confusion.",
            "Encontrar agua no es desinfectar. Abre Hacer el agua menos mala después. Cuidado si no orinas, hay sangre en heces o hay confusión.",
            [
                step(
                    "Shade first. Walk dawn and dusk. Follow drainage downhill in daylight — green, bird noise at water hours, rock tinajas after rain. Do not drink urine, seawater, radiator fluid, or a cactus as your plan.",
                    "Sweat is water you already had. A cactus is spines. Urine and seawater concentrate the problem.",
                    "Child stays in the shade with an adult. They do not sip the scoop 'to try'.",
                    "Stop if the only water smells like fuel or shines like oil — boiling will not fix chemicals.",
                    "water-boil.png",
                    "Sombra primero. Camina al alba y al anochecer. Sigue el drenaje cuesta abajo de día: verde, aves a hora de agua, tinajas en roca después de lluvia. No bebas orina, agua de mar, radiador ni un cactus como plan.",
                    "El sudor es agua que ya tenías. Un cactus son espinas. La orina y el mar concentran el problema.",
                    "El niño a la sombra con un adulto. No prueba el scoop.",
                    "Para si el único agua huele a combustible o brilla como aceite: el hervor no quita químicos.",
                    party={"1": "Shade, then a named drain.", "2": "One stays with kit, one scouts downhill in voice range.", "4": "Shade / scout / watch / treat."},
                ),
            ],
        ),
        card(
            "water-catch",
            "water",
            "Catch rain and dew",
            "Atrapa lluvia y rocío",
            "Sky is working or dawn is wet on metal. You need a bottle more than a walk.",
            "El cielo trabaja o el alba moja el metal. Necesitas una botella más que una caminata.",
            [
                ("You already have sealed water.", "Ya tienes agua sellada."),
                ("Lightning is on top of you — catch later, get off the high point now.", "El rayo está encima: atrapa después, baja del alto ahora."),
            ],
            "Caught water still needs the boil card unless it fell into a clean closed bottle. Care for gut illness the same as any other field water.",
            "El agua atrapada aún necesita el hervor salvo que cayó en una botella limpia cerrada. El mal de estómago es el mismo.",
            [
                step(
                    "Tarp, poncho, bag, or a clean rock hollow into a bottle. Divert the first dirty minute off the cloth, then catch. At dawn wipe dew off metal or plastic into the same bottle. A pit still often returns less than you sweat — do not count on it.",
                    "Rain is the honest field catch. A still that costs a day's digging is usually a loss.",
                    "Child holds the bottle, not the ridgeline in a storm.",
                    "Stop catching if the cloth was a chemical tarp or a fuel bag — that catch is not water.",
                    "water-boil.png",
                    "Lona, poncho, bolsa o hueco limpio de roca a una botella. Desvía el primer minuto sucio, luego atrapa. Al alba pasa rocío de metal o plástico a la misma botella. Un alambique en pozo suele devolver menos de lo que sudas: no cuentes con él.",
                    "La lluvia es la captura honesta. Un alambique que cuesta un día de cavar suele ser pérdida.",
                    "El niño sostiene la botella, no la cumbrera en la tormenta.",
                    "Para si la lona era química o de combustible: eso no es agua.",
                ),
            ],
        ),
        card(
            "fire-spark",
            "fire",
            "Fire from what you have",
            "Fuego con lo que tienes",
            "You need heat for water or to not die of wet cold. You may have a spark, a battery, a lens, or only sticks.",
            "Necesitas calor para agua o para no morir de frío mojado. Puede que tengas chispa, batería, lupa o solo palos.",
            [
                ("You have a working stove on mineral soil.", "Tienes estufa funcionando sobre suelo mineral."),
                ("Red-flag wind or a fire you cannot kill — do not start another.", "Viento extremo o un fuego que no puedes matar: no inicies otro."),
            ],
            "Burns go to care. This is a cook and rewarm fire, not a wildfire. If friction is all you have and daylight is going, stop and build the roof first.",
            "Las quemaduras van a cuidado. Esto es fuego de cocina y recalentar, no un incendio. Si solo tienes fricción y se acaba el día, para y haz el techo primero.",
            [
                step(
                    "Mineral soil, ring or pit, water or dirt in hand. Shred tinder you can (inner bark, dry grass, cotton, tape fuzz). Spark in this order: match or ferro, then lens on black char, then battery on steel wool if you have both. Friction last — bow or hand drill fails when wet or rushed. Do not spend the last daylight on it unless you already can.",
                    "Tinder and a kill method beat a pretty spark. Friction is a skill, not a feeling.",
                    "Child fetches dead twigs outside the ring. They do not blow the coal or hold the battery.",
                    "Stop if embers run into grass you cannot stamp. Lid or dirt, not panic water on grease.",
                    "fire-ring.png",
                    "Suelo mineral, aro o pozo, agua o tierra en la mano. Desmenuza yesca (corteza interna, pasto seco, algodón). Chispa en este orden: fósforo o ferro, luego lupa sobre carbón negro, luego batería en lana de acero si tienes ambas. Fricción al último: el taladro falla mojado o con prisa. No gastes la última luz del día en eso salvo que ya sepas.",
                    "La yesca y cómo matarlo ganan a una chispa bonita. La fricción es oficio, no un sentimiento.",
                    "El niño trae ramitas fuera del aro. No sopla la brasa ni sostiene la batería.",
                    "Para si las brasas se van al pasto y no puedes pisarlas. Tapa o tierra, no agua de pánico en grasa.",
                    party={"1": "Tinder, spark, kill pile.", "2": "One sparks, one fetches deadfall.", "4": "Tinder / spark / fuel / watch the grass."},
                ),
                step(
                    "Feed pencil sticks then wrist-thick. Bank coals in ash if you must keep heat overnight. Kill it dead before you walk — stir, water or dirt, hand over the ash.",
                    "A fire you did not kill is how a camp becomes a country problem.",
                    "Child stays outside the ring while you kill it.",
                    "Stop and stay if you cannot put a hand on the ash. Do not walk away from heat you cannot check.",
                    "fire-ring.png",
                    "Alimenta palitos, luego muñeca. Guarda brasas en ceniza si debes guardar calor de noche. Mátelo del todo antes de caminar: remueve, agua o tierra, mano sobre la ceniza.",
                    "Un fuego que no mataste es cómo un campamento se vuelve problema del país.",
                    "El niño fuera del aro mientras lo matas.",
                    "Quédate si no puedes poner la mano en la ceniza. No te vayas de un calor que no puedes revisar.",
                ),
            ],
        ),
        card(
            "shelter-site",
            "shelter",
            "Pick the camp before you build",
            "Elige el campamento antes de construir",
            "Night or weather is coming. The roof is the next card. The ground you pick is this one.",
            "Viene noche o clima. El techo es la siguiente tarjeta. El suelo que eliges es esta.",
            [
                ("You already have a closed tent on high drained ground.", "Ya tienes tienda cerrada en alto drenado."),
                ("The cut is talking or the sky is a storm on a ridge — move first.", "La quebrada habla o el cielo es tormenta en un filo: muévete primero."),
            ],
            "A bad site makes hypothermia and flood. Get to care for shivering that stops and speech that slurs.",
            "Un mal sitio hace hipotermia y creciente. Busca cuidado si deja de temblar y habla raro.",
            [
                step(
                    "High, drained ground. Not in a wash. Not under a widowmaker. Not on a ridge in a storm. Wind at the back wall. Water downhill of camp, not through it. Escape route you can walk in the dark. Then build the tarp or debris lean-to.",
                    "The roof cannot fix a river bed. Widowmakers kill in wind you have not felt yet.",
                    "Child sits on the pack off the dirt while you pick. They do not climb the dead tree.",
                    "Stop and move if water is already running where you wanted the floor, or if a trunk is cracked overhead.",
                    "shelter-tarp.png",
                    "Suelo alto y drenado. No en un arroyo. No bajo un árbol viudo. No en un filo con tormenta. Viento a la pared de atrás. Agua cuesta abajo del campamento, no a través. Ruta de escape que puedas caminar de noche. Luego la lona o el refugio de restos.",
                    "El techo no arregla un cauce. Los viudos matan con un viento que aún no sientes.",
                    "El niño se sienta en la mochila, no en la tierra, mientras eliges. No sube al árbol muerto.",
                    "Muévete si ya corre agua donde querías el piso, o si hay un tronco rajado arriba.",
                    party={"1": "Pick, then build.", "2": "One picks, one gathers debris off the floor line.", "4": "Site / roof / floor / watch."},
                ),
            ],
        ),
        card(
            "sig-ground",
            "signaling",
            "Smoke, three, and open ground",
            "Humo, tres y suelo abierto",
            "You need a plane, a ridge party, or a road to notice you. Mirror is the other card. This is the mark they can see without a flash.",
            "Necesitas que un avión, un grupo en el filo o un camino te vean. El espejo es la otra tarjeta. Esta es la marca que se ve sin destello.",
            [
                ("You already have voice with the party that is looking.", "Ya tienes voz con el grupo que te busca."),
                ("A fire for smoke would take the grass — move to mineral soil first.", "Un fuego para humo se llevaría el pasto: primero suelo mineral."),
            ],
            "Signaling is not a phone. If someone is dying, offer Emergency SOS when a net exists, then keep the mark working.",
            "Señalar no es un teléfono. Si alguien se muere, ofrece Emergency SOS si hay red, y sigue con la marca.",
            [
                step(
                    "Open ground. Contrast. Three of anything — fires, rocks, panels, whistle blasts. Smoke by day on mineral soil, fire by night. Save the battery for a window someone can actually see. Do not burn the country.",
                    "One smudge in timber is a camp. Three on a bald is a request.",
                    "Child can hold a panel still. They do not tend the signal fire.",
                    "Stop the smoke if wind takes embers into grass you cannot stamp.",
                    "signal-three.png",
                    "Suelo abierto. Contraste. Tres de cualquier cosa: fuegos, piedras, paneles, silbatazos. Humo de día en suelo mineral, fuego de noche. Guarda la batería para una ventana que alguien pueda ver. No quemes el país.",
                    "Una humareda en el monte es un campamento. Tres en un calvo es un pedido.",
                    "El niño puede sostener un panel. No cuida el fuego de señal.",
                    "Para el humo si el viento lleva brasas al pasto y no puedes pisarlas.",
                    party={"1": "Pick a bald and make three.", "2": "One marks, one watches the grass.", "4": "Mark / smoke / watch / stay put."},
                ),
            ],
        ),
        card(
            "camp-latrine",
            "tactics",
            "Latrine downhill of camp",
            "Letrina cuesta abajo del campamento",
            "The camp will last more than a night. Gut bugs are how a party folds.",
            "El campamento durará más de una noche. Los bichos del intestino doblan al grupo.",
            [
                ("You are moving in an hour and can walk it well away from water.", "Te mueves en una hora y puedes irlo lejos del agua."),
                ("Someone already has bloody stool or no urine — that is the gut card and care, not a hole.", "Alguien ya tiene sangre en heces o no orina: eso es la tarjeta de intestino y cuidado, no un hoyo."),
            ],
            "Hands and distance keep the water you just treated. Care for gut illness that will not keep fluids down.",
            "Manos y distancia guardan el agua que acabas de tratar. Cuidado si el mal de estómago no retiene líquidos.",
            [
                step(
                    "Walk ~60 paces downslope and away from the water you drink. Hole, then cover. Pack out paper if you can. Wash hands with treated water before you cook. This is how camps last.",
                    "A latrine uphill of the bottle is a slow poison.",
                    "Child uses the same hole with an adult, not a private bush next to the creek.",
                    "Stop and move camp if you already dug through into the water table or a smell is in the kitchen.",
                    "form-up.png",
                    "Camina unos 60 pasos cuesta abajo y lejos del agua que bebes. Hoyo, luego tapa. Lleva el papel si puedes. Lávate con agua tratada antes de cocinar. Así duran los campamentos.",
                    "Una letrina río arriba de la botella es un veneno lento.",
                    "El niño usa el mismo hoyo con un adulto, no un matorral junto al arroyo.",
                    "Mueve el campamento si ya cavaste hasta el agua o el olor está en la cocina.",
                    party={"1": "Downhill, cover, wash.", "2": "One cooks, one does not share that hand until washed.", "4": "Kitchen / water / latrine / wash are four jobs."},
                ),
            ],
        ),
        card(
            "med-gut",
            "medical",
            "Gut illness — keep fluids",
            "Mal de estómago — retén líquidos",
            "Vomiting, diarrhea, or both. The danger is the water leaving, not the hours of misery.",
            "Vómito, diarrea o ambos. El peligro es el agua que se va, no las horas de miseria.",
            [
                ("They can drink, make urine, and the stool is not bloody.", "Pueden beber, orinar y la hez no tiene sangre."),
                ("They cannot sit, there is blood, no urine, or they are confused — this is care, not a sip plan.", "No se sientan, hay sangre, no orinan o están confundidos: es cuidado, no un plan de sorbos."),
            ],
            "Get to care for bloody stool, no urine, a stiff belly, or confusion. Do not plug it with a mystery plant.",
            "Busca cuidado si hay sangre en heces, no orinas, vientre duro o confusión. No lo tapes con una planta misteriosa.",
            [
                step(
                    "Sit in shade. Sips of treated water. A pinch of salt and a pinch of sugar in a bottle if you have them. Small and often. Cool cloth. No mystery tea. No anti-diarrhea plant.",
                    "The body is emptying. Replace water and salt. A plug keeps the toxin in.",
                    "Child sips sitting up. Do not force a bottle into a vomiting mouth.",
                    "Stop oral fluids if they cannot sit or keep choking. Roll, clear, get to care.",
                    "food-boil.png",
                    "Sombra. Sorbos de agua tratada. Una pizca de sal y una de azúcar en la botella si las tienes. Poco y seguido. Paño fresco. Sin té misterioso. Sin planta antidiarrea.",
                    "El cuerpo se vacía. Repón agua y sal. Un tapón deja adentro la toxina.",
                    "El niño sorbe sentado. No fuerces un botella en una boca que vomita.",
                    "Nada por boca si no se sientan o se ahogan. Gira, limpia, busca cuidado.",
                    tick_s=600,
                    party={"1": "Shade and sips.", "2": "One sips them, one treats the next bottle.", "4": "Sips / shade / water treat / watch urine."},
                ),
            ],
        ),
        card(
            "med-burn",
            "trauma",
            "Burn — cool then cover",
            "Quemadura — enfría luego cubre",
            "Heat, steam, grease, or coals got skin. The next hour sets the depth.",
            "Calor, vapor, grasa o brasas en la piel. La próxima hora fija la profundidad.",
            [
                ("It is a small reddened patch, they are talking, and you can keep it clean.", "Es un parche rojo chico, hablan y puedes mantenerlo limpio."),
                ("Face, hands, genitals, blistered sheets, white or charred skin, or they are fading — this is care now.", "Cara, manos, genitales, sábanas de ampollas, piel blanca o carbonizada, o se apagan: es cuidado ahora."),
            ],
            "Cool, cover, get to care for anything that is not a small red patch. Offer Emergency SOS if a net exists.",
            "Enfría, cubre, busca cuidado si no es un parche rojo chico. Ofrece Emergency SOS si hay red.",
            [
                step(
                    "Cool with water — treated if you can, cleanest you have — for several minutes. Then a loose clean cover. No butter, no toothpaste, no ice packed onto a deep burn, no peeling the skin. Rings come off before swell.",
                    "Heat keeps cooking after the flame is gone. Grease and ice both make it worse.",
                    "A child holds the water bottle. They do not pick blisters.",
                    "Stop cooling if they start to shiver hard — you made a hypothermia problem. Cover and move to care.",
                    "heat-cool.png",
                    "Enfría con agua — tratada si puedes, la más limpia — varios minutos. Luego cobertura suelta y limpia. Sin mantequilla, sin pasta, sin hielo apretado en una quemadura honda, sin pelar. Anillos fuera antes de que hinche.",
                    "El calor sigue cocinando cuando ya no hay llama. La grasa y el hielo empeoran.",
                    "El niño sostiene la botella. No pincha ampollas.",
                    "Para de enfriar si tiemblan recio: ya hiciste hipotermia. Cubre y mueve a cuidado.",
                    tick_s=180,
                    party={"1": "Cool, cover, walk.", "2": "One cools, one fetches clean cloth.", "4": "Cool / cover / kit / watch airway."},
                ),
            ],
        ),
        card(
            "med-feet",
            "medical",
            "Hot spot on a foot",
            "Punto caliente en un pie",
            "A rub that will be a hole by tomorrow. Infection is how a walk ends.",
            "Un roce que mañana será un hueco. La infección es cómo termina una caminata.",
            [
                ("Skin is intact and you can pad it.", "La piel está intacta y puedes almohadillarla."),
                ("Red streak, pus, fever, or they cannot take weight — that is infection and care.", "Raya roja, pus, fiebre o no carga peso: es infección y cuidado."),
            ],
            "A hole in the foot is not toughness. Care for spreading red, pus, or a foot they will not stand on.",
            "Un hueco en el pie no es aguante. Cuidado si el rojo se extiende, hay pus o no se paran.",
            [
                step(
                    "Stop. Dry the foot. Tape or pad the hot spot before it opens. Sock dry, grit out of the shoe. Do not pop what you can still pad. Next rest, look at the other foot too.",
                    "Ten minutes now is a day of walking later.",
                    "Child's shoes come off at the first complaint. No 'walk it off'.",
                    "Stop the miles if the skin is already a wet hole you cannot keep clean — pad, rest, care.",
                    "fracture-splint.png",
                    "Para. Seca el pie. Cinta o almohadilla en el punto caliente antes de que abra. Calceta seca, tierra fuera del zapato. No pinches lo que aún puedes tapar. En el siguiente descanso, mira el otro pie.",
                    "Diez minutos ahora son un día de caminar después.",
                    "Los zapatos del niño salen a la primera queja. Sin 'aguántalo'.",
                    "Para las millas si ya es un hueco húmedo que no puedes limpiar: almohadilla, descanso, cuidado.",
                ),
            ],
        ),
        card(
            "env-flood",
            "environment",
            "Get out of the wash",
            "Sal del arroyo",
            "A cut, arroyo, or canyon floor. Rain you cannot see is enough. Night in a wash is how desert parties drown.",
            "Una quebrada, arroyo o piso de cañón. Basta la lluvia que no ves. De noche en un arroyo es cómo se ahogan los grupos del desierto.",
            [
                ("You are already on high ground and the water is not rising toward you.", "Ya estás en alto y el agua no sube hacia ti."),
                ("Someone is in moving water you cannot stand in — that is a crossing emergency, not a camp move.", "Alguien está en agua que no puedes pisar: es emergencia de cruce, no un mudanza de campamento."),
            ],
            "High ground is the treatment. Get to care for anyone who went under or swallowed muddy water and now cannot breathe right.",
            "El alto es el tratamiento. Busca cuidado si alguien se sumergió o tragó lodo y ahora no respira bien.",
            [
                step(
                    "If you hear it, see it rise, or the sky up-canyon is a wall — out of the cut now. Leave the pack if the pack is the delay. Night: do not camp in a wash even if it is dry. High ground, count the party, stay off the next cut.",
                    "A desert flood moves faster than a tired walk. Dry sand is not a promise.",
                    "Pick the child up. Do not let them 'run back for the bottle'.",
                    "Stop going back for gear once water has a voice. People, then gear.",
                    "monsoon.png",
                    "Si lo oyes, lo ves subir o el cielo río arriba es una pared: sal de la quebrada ahora. Deja la mochila si la mochila es la demora. De noche: no campees en un arroyo aunque esté seco. Alto, cuenta al grupo, no la siguiente quebrada.",
                    "Una creciente del desierto corre más que un caminar cansado. La arena seca no es promesa.",
                    "Carga al niño. No lo dejes 'volver por la botella'.",
                    "No vuelvas por equipo cuando el agua ya tiene voz. Gente, luego equipo.",
                    party={"1": "Uphill now.", "2": "One carries the child, one counts.", "4": "Uphill / count / light / stay."},
                ),
            ],
        ),
        card(
            "env-lightning",
            "environment",
            "Off the high point",
            "Baja del punto alto",
            "Thunder you can hear, hair that lifts, or a ridge in a build-up. Poles and lone trees are part of the problem.",
            "Trueno que oyes, pelo que se levanta o un filo en un cumulonimbo. Postes y árboles solos son parte del problema.",
            [
                ("The storm is gone and you are off the ridge.", "La tormenta se fue y ya bajaste del filo."),
                ("Someone is down after a strike — airway and CPR cards, not a weather lesson.", "Alguien cayó tras un rayo: tarjetas de vía aérea y RCP, no una lección de clima."),
            ],
            "A strike is trauma and heart. Offer Emergency SOS if a net exists. Get to care even if they 'woke up'.",
            "Un rayo es trauma y corazón. Ofrece Emergency SOS si hay red. Busca cuidado aunque 'haya despertado'.",
            [
                step(
                    "Off peaks, towers, fence lines, and lone trees. Drop poles and long conductors. If it is on you, crouch on a pad or pack, feet together, not lying flat. Wait for the storm to move. The tarp card is not a lightning rod.",
                    "Height and metal collect the hit. A cave mouth and a ridge both want you off them.",
                    "Child in the middle of the group, off the ridgeline, not under the pretty lone tree.",
                    "Stop holding the ridgeline 'for the view for one more minute'. Move.",
                    "heat-island.png",
                    "Baja de picos, torres, alambradas y árboles solos. Suelta postes y cables largos. Si está encima, cuclillas sobre un pad o mochila, pies juntos, no tendido. Espera a que se mueva. La lona no es un pararrayos.",
                    "La altura y el metal recogen el golpe. Una boca de cueva y un filo te quieren fuera.",
                    "El niño al centro del grupo, fuera del filo, no bajo el árbol solo bonito.",
                    "No te quedes en el filo 'un minuto más por la vista'. Muévete.",
                    party={"1": "Down and small.", "2": "Move together, no stragglers on the wire.", "4": "Off the high / count / kit / wait."},
                ),
            ],
        ),
        card(
            "env-desert-day",
            "environment",
            "Shade before miles",
            "Sombra antes que millas",
            "Desert or pavement heat. The party still wants to 'make the next tank' in the white hours.",
            "Calor de desierto o pavimento. El grupo aún quiere 'llegar al siguiente tanque' en las horas blancas.",
            [
                ("It is dawn or dusk, they are drinking, and shade is in reach.", "Es alba o anochecer, beben y hay sombra a mano."),
                ("They stopped sweating or are confused — that is heat collapse, not this card.", "Dejaron de sudar o están confundidos: es colapso por calor, no esta tarjeta."),
            ],
            "Heat stroke is the other card. Cool first if they are already wrong. Care for confusion that does not clear.",
            "El golpe de calor es la otra tarjeta. Enfría primero si ya están mal. Cuidado si la confusión no pasa.",
            [
                step(
                    "Do not march the midday. Cover skin. Sit the south-side shade. Sip treated water. Work dawn and dusk. A wet cloth on the neck is work; a hero mile at 15:00 is how heat collapse starts.",
                    "Sweat you cannot replace is a debt. Shade is the payment plan.",
                    "Child gets the shade and the sip first. No races.",
                    "Stop the walk if urine goes dark or someone stops sweating — open heat collapse.",
                    "heat-cool.png",
                    "No marches el mediodía. Cubre la piel. Siéntate a la sombra del sur. Sorbe agua tratada. Trabaja alba y anochecer. Un paño mojado en el cuello es trabajo; una milla de héroe a las 15:00 es cómo empieza el colapso.",
                    "El sudor que no repones es deuda. La sombra es el plan de pago.",
                    "El niño recibe la sombra y el sorbo primero. Sin carreras.",
                    "Para la caminata si la orina se oscurece o alguien deja de sudar: abre colapso por calor.",
                    party={"1": "Shade and sip.", "2": "One walks the cool hours, one stays with the weak.", "4": "Shade / water / watch / no midday miles."},
                ),
            ],
        ),
        card(
            "env-crossing",
            "environment",
            "Moving water",
            "Agua en movimiento",
            "A creek, river, or acequia you want to be on the other side of. You can still walk around.",
            "Un arroyo, río o acequia al otro lado. Aún puedes rodear.",
            [
                ("You found a bridge, a road, or a place you can step without a push.", "Hay puente, camino o un paso sin empujón."),
                ("It is above the knee and pushing, or you cannot see the bottom — do not.", "Está sobre la rodilla y empuja, o no ves el fondo: no."),
            ],
            "Drowning is care you will not give in the middle. Get to care for anyone who went under.",
            "Ahogarse es un cuidado que no das en medio. Busca cuidado si alguien se sumergió.",
            [
                step(
                    "Walk around if you can. Unbuckle the pack. Face slightly upstream, shuffle, three points. Weak swimmer upstream of the strong one so they are not the battering ram. Child does not free swim. If it is above the knee and pushing, it is a different river — don't.",
                    "A pack that stays buckled is an anchor. Pride at a ford is how parties lose people.",
                    "Carry the child. They are not a float test.",
                    "Stop at the first slip you cannot plant. Back out the way you came.",
                    "water-boil.png",
                    "Rodea si puedes. Destacha la mochila. Cara un poco aguas arriba, pasos cortos, tres puntos. El nadador débil aguas arriba del fuerte para no ser ariete. El niño no nada suelto. Si pasa la rodilla y empuja, es otro río: no.",
                    "La mochila abrochada es ancla. El orgullo en un vado es cómo se pierde gente.",
                    "Carga al niño. No es una prueba de flotación.",
                    "Para en el primer resbalón que no puedes plantar. Sal por donde entraste.",
                    party={"1": "Walk around.", "2": "Rope if you have it; no one belays from a tree you would not trust with a fall.", "4": "Scout / cross / catch / child last in arms."},
                ),
            ],
        ),
        card(
            "plant-cordage",
            "plants",
            "Fiber is cordage, not food",
            "La fibra es cuerda, no comida",
            "You need string: tarp, splint, pack repair. Yucca, agave, dead inner bark, a shoelace. This is not a meal.",
            "Necesitas cuerda: lona, férula, compostura. Yucca, agave, corteza interna muerta, un cordón. Esto no es una comida.",
            [
                ("You already have cord or tape that will hold.", "Ya tienes cuerda o cinta que aguanta."),
                ("Lips or tongue are already burning — that is a medical card, not fiber.", "Labios o lengua ya arden: es médico, no fibra."),
            ],
            "Vision is a guess. Nothing here unlocks a meal. If they chewed the fiber, get to care for vomiting, trouble breathing, or collapse.",
            "Vision es una conjetura. Nada aquí desbloquea una comida. Si masticaron la fibra, busca cuidado.",
            [
                step(
                    "Dead or dropped leaves, not a live strip that kills the plant you may need tomorrow. Scrape, twist, join with a square knot you can undo. Use. Do not chew. Do not make a tea. Wash sap off skin.",
                    "Cordage is a tool. The unknown-plant card is still the rule for anything in a mouth.",
                    "Take the leaf out of a child's mouth. They can hold the finished twist.",
                    "Stop if anyone's mouth tingles or a rash starts — sit, watch airway.",
                    "plant-use.png",
                    "Hojas muertas o caídas, no una tira viva que mata la planta que tal vez necesitas mañana. Raspa, tuerce, une con un nudo cuadrado que puedas deshacer. Úsala. No mastiques. No hagas té. Lava la savia.",
                    "La cuerda es herramienta. La tarjeta de planta desconocida sigue siendo la regla para cualquier cosa en la boca.",
                    "Saca la hoja de la boca del niño. Puede sostener el torcido listo.",
                    "Para si hormiguea la boca o sale sarpullido: sienta, vigila vía aérea.",
                    party={"1": "Twist what you already trust as fiber.", "2": "One twists, one builds.", "4": "Cordage / tarp / splint / watch mouths."},
                ),
            ],
        ),
        card(
            "camp-blade",
            "tactics",
            "Keep the blade",
            "Guarda el filo",
            "You have a knife, saw, or you are about to improvise one. A lost or buried blade is a bad week.",
            "Tienes cuchillo, sierra o vas a improvisar uno. Un filo perdido o enterrado es una semana mala.",
            [
                ("The blade is in the sheath and nobody is cut.", "El filo está en la vaina y nadie está cortado."),
                ("Blood is pulsing — that is pack-a-bleed, not a lecture.", "La sangre pulsa: es taponar, no una lección."),
            ],
            "Cuts go to the bleed card. Get to care for a deep cut, a cut across a palm you need, or bleeding you cannot pack.",
            "Los cortes van a la tarjeta de sangrado. Busca cuidado si es hondo, cruza la palma que necesitas o no puedes taponar.",
            [
                step(
                    "Cut away from the body. Sheath when you walk. Batoning deadfall, not live hardwood you cannot finish. Mark the place you set it down. A rock flake is a last tool — same rules, easier to lose.",
                    "The blade is calories of work. Most field cuts happen on the recover, not the chop.",
                    "Child does not get the blade. They can sit well clear with the wood pile.",
                    "Stop if you are shaking, wet-handed, or working in the dark. Sheath and wait.",
                    "bleed-pack.png",
                    "Corta lejos del cuerpo. Vaina al caminar. Hende madera muerta, no dura viva que no puedes terminar. Marca dónde lo dejaste. Una lasca de piedra es la última herramienta: mismas reglas, más fácil de perder.",
                    "El filo son calorías de trabajo. La mayoría de cortes de campo son al recoger, no al tajar.",
                    "El niño no lleva el filo. Puede sentarse lejos con la pila de leña.",
                    "Para si tiemblas, tienes la mano mojada o trabajas a oscuras. Vaina y espera.",
                    party={"1": "One blade, sheathed between cuts.", "2": "One cuts, one is not in the arc.", "4": "Cut / carry / sheath / first aid."},
                ),
            ],
        ),
        card(
            "env-bog",
            "environment",
            "Mud and standing water",
            "Lodo y agua quieta",
            "A swamp edge, a stock-tank margin, or a bosque that will not let a boot go. Cottonmouth country is the bite card.",
            "Orilla de ciénaga, margen de tanque o un bosque que no suelta la bota. País de mocasín de agua es la tarjeta de mordedura.",
            [
                ("You are on firm ground and the water is a treat-it problem, not a trap.", "Estás en firme y el agua es para tratarla, no una trampa."),
                ("A boot is already gone past the knee and the mud is climbing — this is now, not a later walk.", "La bota ya pasó la rodilla y el lodo sube: es ahora, no un caminar después."),
            ],
            "Standing water is the disinfect card, not a drink. Bite treatment if a snake is in it. Care for anyone who went under.",
            "El agua quieta es la tarjeta de desinfectar, no un trago. Tratamiento de mordedura si hay víbora. Cuidado si alguien se sumergió.",
            [
                step(
                    "Do not yank a buried foot straight up. Unlace, float the body back, crawl to roots or grass. Probe with a stick. Do not drink the standing water untreated. Give snakes the road — still, then the bite card.",
                    "Suction plus panic is how a boot becomes a body. Lean back, not harder in.",
                    "Child does not test the mud. Carry them on firm ground.",
                    "Stop fighting a hole that climbs. Yell, spread weight, wait for a branch, do not dive after a pack.",
                    "monsoon.png",
                    "No tires del pie enterrado hacia arriba. Destacha, flota el cuerpo atrás, gatea a raíces o pasto. Sonda con un palo. No bebas el agua quieta sin tratar. Cede el paso a las víboras: quieto, luego la tarjeta de mordedura.",
                    "Succión más pánico es cómo una bota se vuelve un cuerpo. Inclínate atrás, no más adentro.",
                    "El niño no prueba el lodo. Cárgalo en firme.",
                    "Para de pelear un hueco que sube. Grita, abre peso, espera una rama, no bucees por una mochila.",
                    party={"1": "Back out, then treat water.", "2": "One on firm ground with a stick, one does not yank.", "4": "Probe / pull from firm / bite watch / water."},
                ),
            ],
        ),
        card(
            "med-infection",
            "medical",
            "Red streak, heat, pus",
            "Raya roja, calor, pus",
            "A cut, bite, or blister that is getting worse instead of closing. The clock is now in days, not minutes.",
            "Un corte, mordedura o ampolla que empeora en vez de cerrar. El reloj ahora es de días, no de minutos.",
            [
                ("It is a small clean scab and they have no fever.", "Es una costra chica y limpia y no tienen fiebre."),
                ("Red streak toward the trunk, fever, pus under pressure, or they are fading — this is care.", "Raya roja hacia el tronco, fiebre, pus a presión o se apagan: es cuidado."),
            ],
            "Field cleaning is not an antibiotic. Get to care for a streak, fever, or a wound that smells like death. Offer Emergency SOS if a net exists.",
            "Limpiar en el campo no es un antibiótico. Busca cuidado si hay raya, fiebre o una herida que huele a muerte. Ofrece Emergency SOS si hay red.",
            [
                step(
                    "Wash with treated water. Cover clean and loose. Watch the edge and the time. Do not pack mud, dung, or a mystery poultice on it. Rest the limb. If a streak runs toward the heart or fever starts, you are walking to care, not waiting on a plant.",
                    "Dirt is not a seal. Time and redness are the honest field test.",
                    "Child's wound gets the clean cloth, not a creek dunk 'because it is cold'.",
                    "Stop the poultice experiment if it burns or the red grows — wash off, cover, go.",
                    "bleed-pack.png",
                    "Lava con agua tratada. Cubre limpio y suelto. Mira el borde y la hora. No pongas lodo, estiércol ni emplasto misterioso. Reposa la extremidad. Si una raya corre al corazón o empieza fiebre, caminas a cuidado, no esperas una planta.",
                    "La tierra no es un sello. Tiempo y rojo son el test honesto de campo.",
                    "La herida del niño lleva tela limpia, no un chapuzón en el arroyo 'porque está frío'.",
                    "Para el emplasto si quema o el rojo crece: lava, cubre, vete.",
                    tick_s=3600,
                    party={"1": "Clean, cover, watch.", "2": "One treats, one prepares the walk to care.", "4": "Clean / cover / fever watch / carry kit."},
                ),
            ],
        ),
        card(
            "camp-watch",
            "tactics",
            "Night watch and food off the ground",
            "Vigilia de noche y comida fuera del suelo",
            "Animals are working the camp, or you are in country that will. Sleep is a shift, not a collapse.",
            "Los animales trabajan el campamento, o estás en país que lo hará. Dormir es un turno, no un desplome.",
            [
                ("You are moving at first light and the food is sealed on you.", "Te mueves al primer luz y la comida va sellada encima."),
                ("A person is missing at night — that is form-up and lost, not a food hang.", "Falta una persona de noche: es formar y perdido, no un colgado de comida."),
            ],
            "Give mammals the road. A bite is the bite card. Do not turn a night noise into a hunt.",
            "Cede el paso a los mamíferos. Una mordedura es la tarjeta de mordedura. No conviertas un ruido de noche en una caza.",
            [
                step(
                    "Food sealed and off the ground, away from where you sleep. Cook downwind of the bags. One person awake if animals are already working the camp. Light and voice, not a chase. Do not sleep on the trail. Give it the road.",
                    "A camp is an invitation. Distance and a watch beat a pile next to your head.",
                    "Child sleeps in the middle, not at the edge with the snacks.",
                    "Stop shouting into the dark and walking after glowing eyes. Stand your ground or leave together.",
                    "animal-bite.png",
                    "Comida sellada y fuera del suelo, lejos de donde duermes. Cocina aguas abajo de las bolsas. Una persona despierta si los animales ya trabajan el campamento. Luz y voz, no una persecución. No duermas en el sendero. Cede el paso.",
                    "Un campamento es una invitación. Distancia y vigilia ganan a un montón junto a la cabeza.",
                    "El niño duerme al centro, no al borde con los dulces.",
                    "Para de gritar a la oscuridad y caminar tras ojos que brillan. Afirma o váyanse juntos.",
                    party={"1": "Hang or bag the food, then sleep light.", "2": "Shifts.", "4": "Food / fire / watch / sleep in pairs."},
                ),
            ],
        ),
        card(
            "env-insect",
            "environment",
            "Ticks, mites, and mosquitoes",
            "Garrapatas, ácaros y mosquitos",
            "Warm country, bosque, or standing water. The bite you do not see is the one that costs a week.",
            "País cálido, bosque o agua quieta. La picadura que no ves es la que cuesta una semana.",
            [
                ("You checked, nothing is buried, and the itch is a welt you can leave alone.", "Revisaste, no hay nada enterrado y el comezón es un ronchón que puedes dejar."),
                ("A tick's head is in, a bullseye rash, fever, or they cannot breathe after a sting — that is care, not a tweeze.", "Hay cabeza de garrapata, un ojo de buey, fiebre o no respiran tras un aguijón: es cuidado, no una pinza."),
            ],
            "A fever after a tick or a spreading rash is care. Airway if a sting swells the face. Do not burn a tick out.",
            "Fiebre después de una garrapata o un sarpullido que crece es cuidado. Vía aérea si un aguijón hincha la cara. No quemes la garrapata.",
            [
                step(
                    "Camp off stagnant water if you can. Sleeves at dusk. End of day: look at warm folds, hairline, socks. Tweeze a tick close to the skin, pull steady, do not twist and do not fire. Watch the spot. Leave chigger welts alone except clean and not scratching into a hole.",
                    "Most of this is prevention and a look. Fire and kerosene on skin make a burn card.",
                    "Check the child first. They do not pull ticks with fingernails in the dark.",
                    "Stop burning, smothering with oil, or digging. If the mouth is in and you cannot tweeze, get to care.",
                    "animal-bite.png",
                    "Campamento lejos del agua estancada si puedes. Mangas al anochecer. Al fin del día: pliegues, raya del pelo, calcetas. Pinza la garrapata junto a la piel, tira firme, no gires ni uses fuego. Mira el sitio. Los ácaros: limpio y sin rascar hasta hacer hueco.",
                    "Casi todo esto es prevención y una mirada. Fuego y keroseno en la piel hacen una tarjeta de quemadura.",
                    "Revisa al niño primero. No sacan garrapatas con uñas a oscuras.",
                    "Nada de quemar, ahogar con aceite o cavar. Si la boca quedó y no puedes pinzar, busca cuidado.",
                    party={"1": "Check at dark.", "2": "Check each other.", "4": "Sleeves / site / check / watch fever."},
                ),
            ],
        ),
    ]


def write_images(cards: list[dict]) -> None:
    img_root = ROOT / "Resources" / "Field" / "images"
    seen = set()
    for c in cards:
        kind = c["category"]
        for st in c["steps"]:
            name = st["image"]
            if name in seen:
                continue
            seen.add(name)
            diagram_png(img_root / name, kind, name)
    for orphan in img_root.glob("*.png"):
        if orphan.name not in seen:
            orphan.unlink()


def write_all() -> None:
    core = core_cards() + thickness_core() + from_nothing_core()
    extra = state_cards() + thickness_state()
    all_cards = core + extra
    write_images(all_cards)
    field_root = ROOT / "Resources" / "Field"
    for stale in field_root.glob("field.*.json"):
        book = stale.stem.split(".")[-1]
        if book != "core" and book.upper() not in SHIPPED_STATES:
            stale.unlink()
    write_json(
        field_root / "field.core.json",
        {
            "schema": "1.4",
            "id": "field.core",
            "cards": [c for c in core],
        },
    )
    for state in SHIPPED_STATES:
        write_json(
            field_root / f"field.{state.lower()}.json",
            {
                "schema": "1.4",
                "id": f"field.{state.lower()}",
                "state": state,
                "cards": [c for c in extra if state in c["states"]],
            },
        )
    print(f"field cards: {len(core)} core + {len(extra)} state")
