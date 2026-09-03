"""Generate field.core + per-state Field JSON (v1.4 schema, EN+ES)."""
from __future__ import annotations

from .common import ROOT, diagram_png, write_json

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
) -> dict:
    return {
        "schema": "1.4",
        "id": cid,
        "category": category,
        "states": states or ["TX", "NM", "FL", "NY"],
        "title": {"en": title, "es": title_es},
        "situation": {"en": situation, "es": situation_es},
        "stop_if": [{"en": a, "es": b} for a, b in stop_if],
        "get_to_care": {"en": get_to_care, "es": get_to_care_es},
        "speak": speak,
        "sendToParty": True,
        "steps": steps,
    }


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
            "Get trained help and an AED. This card does not replace Emergency SOS or 911.",
            "Consigue ayuda entrenada y un DEA. Esta tarjeta no reemplaza Emergency SOS ni el 911.",
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
            "Pavement, no shade, and a party still moving in El Paso, Austin, Miami, or Jacksonville afternoon.",
            "Pavimento, sin sombra, y el grupo sigue en la tarde de El Paso, Austin, Miami o Jacksonville.",
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
            states=["TX", "FL"],
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
            "Sandia or high NM rock with a film of ice. Same problem as Adirondack ledge ice — not a Florida card.",
            "Roca alta de Sandia con una película de hielo. El mismo problema que el hielo de cornisa en Adirondacks.",
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
            states=["NM", "NY"],
        ),
        card(
            "fl-rip",
            "water",
            "Rip current",
            "Corriente de resaca",
            "Florida beach. The party is being pulled off the sand. No live NWS — you have eyes and a procedure.",
            "Playa de Florida. El grupo se va mar adentro. Sin NWS en vivo: ojos y procedimiento.",
            [("You are already back in thigh-deep water that is not pulling.", "Ya estás en agua a los muslos que no jala.")],
            "Drowning is care you cannot do past CPR on the sand. Offer Emergency SOS from the beach, not from the rip.",
            "El ahogo es cuidado que no das más allá de RCP en la arena. Emergency SOS desde la playa, no desde la resaca.",
            [
                step(
                    "Do not fight straight in. Swim parallel to the beach until the pull eases, then angle in. If you cannot swim, float and raise an arm. Shore party does not make a second victim.",
                    "The rip is a narrow river. Sideways exits it.",
                    "A child in a rip: throw a board or line if you have it. Do not send another child.",
                    "Stop the hero swim if you are already tired on the sand.",
                    "rip.png",
                    "No pelees derecho a la orilla. Nada paralelo hasta que afloje, luego en ángulo. Si no nadas, flota y alza un brazo.",
                    "La resaca es un río angosto. De lado se sale.",
                    "Niño en la resaca: lanza tabla o cuerda. No mandes a otro niño.",
                    "No hagas el nado héroe si ya estás cansado en la arena.",
                    party={"1": "Float, signal, parallel.", "2": "One swims parallel; one stays on sand with eyes and SOS offer.", "4": "Two on sand (spot + SOS), one throw bag, one swimmer max."},
                )
            ],
            states=["FL"],
        ),
        card(
            "fl-gator-dusk",
            "animals",
            "Gator at dusk",
            "Caimán al anochecer",
            "Fresh water in Florida. Dusk, a dog, or a kid at the edge. This card does not exist in NY packs.",
            "Agua dulce en Florida. Anochecer, un perro o un niño en la orilla. Esta tarjeta no existe en packs de NY.",
            [("You are already well back from the waterline and the animal is gone.", "Ya estás lejos de la orilla y el animal se fue.")],
            "A bite is a bleed and a trauma hospital. Do not 'move the gator'.",
            "Una mordida es hemorragia y hospital de trauma. No 'muevas al caimán'.",
            [
                step(
                    "Leash the dog. Child in hand, not at the bloom of water. Do not feed. If you see eyes, back up on the same path. Night: torch 3× at the bank before you fill bottles.",
                    "They hunt the edge. You do not need to win a stare.",
                    "No wading 'just to the knees' at dusk.",
                    "Stop fishing that hole if a slide mark is fresh.",
                    "gator-dusk.png",
                    "Perro con correa. Niño de la mano. No alimentes. Si ves ojos, retrocede por el mismo camino. Noche: linterna 3× antes de llenar botellas.",
                    "Cazan la orilla. No tienes que ganar la mirada.",
                    "Sin meterse 'hasta las rodillas' al anochecer.",
                    "No pesques ese hueco si la marca de arrastre está fresca.",
                )
            ],
            states=["FL"],
        ),
        card(
            "fl-keys-mm",
            "nav",
            "Keys mile marker",
            "Milla de los Keys",
            "Overseas Highway. Mile markers are the handrail. Hospitals and exits are sparse.",
            "Carretera Overseas. Las millas son la baranda. Hospitales y salidas son pocos.",
            [("You know the last MM and the next town.", "Sabes la última MM y el próximo pueblo.")],
            "A wreck on a two-lane causeway is care that has to come from a marked MM.",
            "Un choque en un puente de dos carriles necesita una MM marcada.",
            [
                step(
                    "Write the mile marker on the trip brief and the paper sheet. If you stop, stand off the pavement. Hurricane: this card is a road, not a shelter.",
                    "Without an MM, help cannot find a dot in the water.",
                    "Kids stay in the vehicle if you are on a narrow shoulder.",
                    "Stop walking the bridge in a storm — there is no honest high ground.",
                    "keys-mm.png",
                    "Anota la milla en el brief y en el papel. Si paras, fuera del pavimento.",
                    "Sin MM, no encuentran un punto en el agua.",
                    "Los niños en el vehículo si el acotamiento es estrecho.",
                    "No camines el puente en tormenta.",
                )
            ],
            states=["FL"],
        ),
        card(
            "fl-hurricane-paper",
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
            states=["FL", "TX"],
        ),
        card(
            "ny-subway-north",
            "nav",
            "Subway — walk north to air",
            "Metro — camina al norte al aire",
            "NYC underground. You need out. Station names and north are the handrail. Not a gator card.",
            "Bajo tierra en NYC. Necesitas salir. Los nombres de estación y el norte son la baranda.",
            [("You can see sky and a street plate.", "Ves cielo y una placa de calle.")],
            "Smoke or a crush is care on the platform. Do not go deeper 'to find a better train'.",
            "Humo o una estampida es cuidado en el andén. No bajes más 'a buscar un tren mejor'.",
            [
                step(
                    "Follow the walkway toward the numbered street increase if you already know you entered south — or follow EXIT signs to the street, then check the map pack. Stay off the track bed unless the platform is on fire.",
                    "The tunnel is not a trail. Trains still move.",
                    "Child's hand. No scavenger hunt down the tube.",
                    "Stop if you hear a train — wall, face in, wait.",
                    "subway-north.png",
                    "Sigue la pasarela a la salida, luego el pack. No bajes a las vías salvo que el andén arda.",
                    "El túnel no es un sendero. Los trenes siguen.",
                    "Mano del niño. Sin explorar el tubo.",
                    "Si oyes tren: pared, cara adentro, espera.",
                )
            ],
            states=["NY"],
        ),
        card(
            "ny-ice-adk",
            "environment",
            "Adirondack ice",
            "Hielo de Adirondacks",
            "Upstate ledge, spring crust, or a waterfall path. Florida packs must not show this card.",
            "Cornisa del norte del estado, costra de primavera o una ruta de cascada. Los packs de Florida no deben mostrar esta tarjeta.",
            [("You turned around to dirt.", "Ya diste la vuelta a la tierra.")],
            "A sliding fall into a drainage is a trauma evac.",
            "Una caída a un desagüe es evacuación de trauma.",
            [
                step(
                    "Turn around early. If you continue, one at a time, spots below, no glissade on unknown runouts. Paper the turnaround time on the party timer.",
                    "Ice under leaves is how Adirondack afternoons go bad.",
                    "Kids do not 'ski' the slab on their shoes.",
                    "Stop if the last pip shows you still above the ice line at dusk.",
                    "adk-ice.png",
                    "Da la vuelta temprano. Si sigues, uno por uno, nadie trineo en una salida desconocida.",
                    "El hielo bajo las hojas es cómo se pone mala la tarde.",
                    "Los niños no 'esquían' la losa.",
                    "Para si el último pip te deja sobre la línea de hielo al oscurecer.",
                )
            ],
            states=["NY"],
        ),
        card(
            "tx-nm-border-hospital",
            "medical",
            "Border hospitals",
            "Hospitales de la frontera",
            "El Paso / southern NM. Trauma may be on one side of a line you cannot see on a dirt road.",
            "El Paso / sur de NM. El trauma puede estar de un lado de una línea que no ves en un camino de tierra.",
            [("You already have a named hospital from the pack POI list.", "Ya tienes un hospital con nombre de la lista POI del pack.")],
            "This card lists how to use the pack POIs. It does not replace 911 or a Border Patrol roadblock decision.",
            "Esta tarjeta dice cómo usar los POI del pack. No reemplaza al 911.",
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
            "A limb is bent where it should not bend, or they cannot take weight after a fall. Skin is closed. No eat-from-photo. No 911 auto-dial.",
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
            "Rewarm trunk first. Get to care for confusion that does not clear. This card does not replace Emergency SOS.",
            "Recalienta el tronco primero. Busca cuidado si la confusión no pasa. No reemplaza Emergency SOS.",
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
    ]


def thickness_state() -> list[dict]:
    """Snake and plant-danger of that state. No cross-coast leak. No edible unlock."""
    snakes = [
        (
            "tx-snake",
            ["TX"],
            "Texas pit viper",
            "Víbora de Texas",
            "West Texas or East Texas brush. Western diamondback or copperhead country. Do not catch it for a photo ID.",
            "Matorral de Texas. Cascabel del oeste o cabeza de cobre. No la atrapes para identificarla.",
            "Western diamondback / copperhead: keep the bitten limb still at heart level. No ice, no cut, no suck, no tourniquet.",
            "Cascabel / cabeza de cobre: extremidad quieta a la altura del corazón. Sin hielo, sin cortar, sin chupar, sin torniquete.",
        ),
        (
            "nm-snake",
            ["NM"],
            "New Mexico rattlesnake",
            "Cascabel de Nuevo México",
            "Prairie or western diamondback on rock or arroyo shade. Do not pin it with a stick.",
            "Cascabel de pradera o del oeste en roca o sombra de arroyo. No la claves con un palo.",
            "Same US pit-viper rule: still limb, walk out if you can, Emergency SOS if a net exists.",
            "Misma regla de víbora de foseta: extremidad quieta, camina si puedes, Emergency SOS si hay red.",
        ),
        (
            "fl-snake",
            ["FL"],
            "Florida cottonmouth / diamondback",
            "Boca de algodón / cascabel de Florida",
            "Water edge or palmetto. Cottonmouth or eastern diamondback. This card does not exist in NY packs.",
            "Orilla o palmito. Boca de algodón o cascabel del este. Esta tarjeta no existe en packs de NY.",
            "Do not 'move the snake off the trail' with your hands. Pit-viper first aid, then care.",
            "No 'quites la culebra del sendero' con las manos. Primeros auxilios de foseta y luego cuidado.",
        ),
        (
            "ny-snake",
            ["NY"],
            "Timber rattlesnake / copperhead",
            "Cascabel de bosque / cabeza de cobre",
            "Hudson ledge or Adirondack talus. Timber rattlesnake or copperhead. No cottonmouth card here.",
            "Cornisa del Hudson o talud de Adirondacks. Cascabel de bosque o cabeza de cobre. Aquí no hay boca de algodón.",
            "Still limb at heart level. No ice. Walk to a road if you can. Florida packs must not show this card.",
            "Extremidad quieta al corazón. Sin hielo. Camina a un camino si puedes. Los packs de Florida no deben ver esta tarjeta.",
        ),
    ]
    plants = [
        (
            "tx-plant-danger",
            ["TX"],
            "Texas plant danger — do not chew",
            "Planta peligrosa de Texas — no mastiques",
            "Oleander hedge or Texas mountain laurel seed. Pretty is not food. No eat-from-photo. Edible unlock is off.",
            "Seto de adelfa o semilla de Texas mountain laurel. Lo bonito no es comida. Sin comer-de-foto.",
            "Oleander and mountain laurel seeds can stop a heart. Do not make tea. Wash sap off skin and eyes with water.",
            "Adelfa y las semillas pueden parar un corazón. No hagas té. Lava savia de piel y ojos con agua.",
        ),
        (
            "nm-plant-danger",
            ["NM"],
            "Datura and jumping cholla",
            "Datura y cholla saltarina",
            "Sacred datura trumpet or a cholla that jumped onto a calf. Do not eat the flower. No edible unlock.",
            "Trompeta de datura o cholla que saltó a una pantorrilla. No comas la flor. Sin desbloqueo comestible.",
            "Datura is a poison, not a medicine card. Cholla: comb it out, do not squeeze with bare hands.",
            "La datura es veneno, no una tarjeta de medicina. Cholla: peine, no aprietes con la mano desnuda.",
        ),
        (
            "fl-plant-danger",
            ["FL"],
            "Manchineel — do not stand under it in rain",
            "Manzanillo — no te pares debajo si llueve",
            "Beach apple on the Florida coast. Sap burns skin and eyes. Fruit is not a snack. This card is FL only.",
            "Manzana de playa en la costa de Florida. La savia quema piel y ojos. El fruto no es tentempié. Solo FL.",
            "Do not take cover under manchineel in rain. Do not burn the wood. Rinse sap with water, then care.",
            "No te refugies bajo el manzanillo si llueve. No quemes la madera. Enjuaga savia con agua y busca cuidado.",
        ),
        (
            "ny-plant-danger",
            ["NY"],
            "Giant hogweed / poison ivy",
            "Hogweed gigante / hiedra venenosa",
            "Road-edge hogweed or a shiny ivy that already itched. Do not eat either. NY only — not a manchineel card.",
            "Hogweed al borde del camino o hiedra brillante que ya pica. No comas ninguna. Solo NY.",
            "Hogweed sap plus sun burns like a chemical. Cover skin, wash with soap, do not scratch open.",
            "La savia de hogweed más sol quema como químico. Cubre piel, lava con jabón, no te rasques hasta abrir.",
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
                        "Back away the way you came. Do not kill or bag the snake. If bitten: sit, still the limb at heart level, walk to a road if you can. Note time. No ice, no cut, no suck, no tourniquet.",
                        "US pit vipers are not treated with jungle-movie first aid. Time to a hospital is the treatment.",
                        "Child stays behind the adult. No stick-poking.",
                        "Stop chasing the snake for 'ID'. A phone photo from far is enough if it is safe.",
                        f"{cid}.png",
                        "Retrocede por donde viniste. No mates ni embolses la culebra. Si hay mordida: sienta, extremidad quieta al corazón, camina a un camino si puedes. Anota la hora.",
                        "Las víboras de foseta de EE. UU. no se tratan como en las películas. El tiempo al hospital es el tratamiento.",
                        "El niño detrás del adulto. Sin pinchar con palo.",
                        "No persigas la culebra para 'identificarla'. Una foto de lejos basta si es seguro.",
                        party={"1": "Sit, still limb, walk out.", "2": "One stays with the bitten, one finds the road.", "4": "Patient / still limb / navigation / SOS offer if a net exists."},
                    )
                ],
                states=states,
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
                        "Do not taste it to 'check'. Brush off, then water on skin and eyes. Do not make a tea or a poultice. Photograph the plant only if you are already clear of sap.",
                        "Eat-from-photo is off. Edible unlock is off. A pretty flower is not a calorie.",
                        "Child does not carry the pretty seed as a toy.",
                        "Stop if they start vomiting or see halos — sit, watch airway, offer Emergency SOS if a net exists.",
                        f"{cid}.png",
                        "No lo pruebes para 'ver'. Sacude, luego agua en piel y ojos. No hagas té ni emplasto.",
                        "Comer-de-foto está apagado. El desbloqueo comestible está apagado.",
                        "El niño no lleva la semilla bonita de juguete.",
                        "Para si vomita o ve halos: sienta, vigila vía aérea, ofrece Emergency SOS si hay red.",
                    )
                ],
                states=states,
                speak=True,
            )
        )
    return out


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


def write_all() -> None:
    core = core_cards() + thickness_core()
    extra = state_cards() + thickness_state()
    all_cards = core + extra
    write_images(all_cards)
    field_root = ROOT / "Resources" / "Field"
    write_json(
        field_root / "field.core.json",
        {
            "schema": "1.4",
            "id": "field.core",
            "cards": [c for c in core],
        },
    )
    for state in ("TX", "NM", "FL", "NY"):
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
