import Foundation
import FieldCorpus

/// Offline first-time walks when the packed book has no hit.
/// Life-threat families start on the move that stops dying. Airplane only.
public enum FieldAskWalk {
    public enum Family: String, Sendable {
        case bleed, cardiac, allergy, choke, cpr, drown, shock, seizure
        case burn, heat, cold, flood, lightning, tornado
        case fracture, lost, eye, nose, animal
        case stroke, head, poison, asthma, avalanche, rip, start
    }

    public static func family(for tokens: Set<String>) -> Family {
        if !tokens.isDisjoint(with: ["bleed", "bleeding", "blood", "cut", "wound", "shot", "stab", "gash", "sangrando"])
            && tokens.isDisjoint(with: ["nose", "nosebleed"])
        {
            return .bleed
        }
        if !tokens.isDisjoint(with: ["cardiac", "chest"]) {
            return .cardiac
        }
        if !tokens.isDisjoint(with: ["allergy", "allergic", "anaphylaxis", "epipen"]) {
            return .allergy
        }
        if !tokens.isDisjoint(with: ["choke", "choking", "airway"]) {
            return .choke
        }
        if !tokens.isDisjoint(with: ["cpr", "unresponsive", "pulse", "unconscious", "collapsed", "fainted"]) {
            return .cpr
        }
        if !tokens.isDisjoint(with: ["drown", "drowning", "drowned"]) {
            return .drown
        }
        if !tokens.isDisjoint(with: ["shock"]) {
            return .shock
        }
        if !tokens.isDisjoint(with: ["seizure", "seizing", "convulsion"]) {
            return .seizure
        }
        if !tokens.isDisjoint(with: ["burn", "scald", "sunburn"]) {
            return .burn
        }
        if !tokens.isDisjoint(with: ["heat", "hot", "calor"]) {
            return .heat
        }
        if !tokens.isDisjoint(with: ["cold", "freezing", "hypothermia", "frio"]) {
            return .cold
        }
        if !tokens.isDisjoint(with: ["flood", "arroyo", "wash"]) {
            return .flood
        }
        if !tokens.isDisjoint(with: ["lightning", "thunder", "thunderstorm", "rayo"]) {
            return .lightning
        }
        if !tokens.isDisjoint(with: ["tornado", "twister", "storm"]) {
            return .tornado
        }
        if !tokens.isDisjoint(with: ["break", "broken", "broke", "sprain", "sling", "fracture"]) {
            return .fracture
        }
        if !tokens.isDisjoint(with: ["lost", "gps", "separated"]) {
            return .lost
        }
        if !tokens.isDisjoint(with: ["eye"]) {
            return .eye
        }
        if !tokens.isDisjoint(with: ["nose", "nosebleed"]) {
            return .nose
        }
        if !tokens.isDisjoint(with: [
            "deer", "hog", "javelina", "coyote", "bear", "lion", "cougar", "puma",
            "elk", "mammal",
        ]) {
            return .animal
        }
        if !tokens.isDisjoint(with: ["stroke", "slurred", "droop"]) {
            return .stroke
        }
        if !tokens.isDisjoint(with: ["concussion", "head"])
            && tokens.isDisjoint(with: ["bleed", "wound", "nose", "nosebleed"])
        {
            return .head
        }
        if !tokens.isDisjoint(with: ["poison", "ingested", "bleach", "overdose"])
            && tokens.isDisjoint(with: ["ivy", "oak", "sumac"])
        {
            return .poison
        }
        if !tokens.isDisjoint(with: ["asthma", "inhaler", "wheezing", "wheeze"]) {
            return .asthma
        }
        if !tokens.isDisjoint(with: ["avalanche"]) {
            return .avalanche
        }
        if !tokens.isDisjoint(with: ["rip", "undertow"]) {
            return .rip
        }
        return .start
    }

    public static func build(
        query: String,
        chapter: [FieldCard],
        packId: String?,
        locale: String
    ) -> FieldCard {
        let toks = Set(FieldCorpus.situationWords(query))
        let asked = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookPic = picture(chapter)
        let bleedPic = picture(chapter, prefer: "bleed-pack.png")
        let family = family(for: toks)
        let urgent: Set<Family> = [
            .bleed, .cardiac, .allergy, .choke, .cpr, .drown,
            .stroke, .poison, .asthma, .avalanche, .rip,
        ]
        let start: [FieldStep] = urgent.contains(family) ? [] : [
            step(
                "Stop. Look around. Do not run.",
                "Para. Mira alrededor. No corras.",
                "Stand still. Hold a grown-up's hand if one is there.",
                "Quédate quieto. Toma la mano de un adulto si hay uno.",
                "Running makes you miss the danger and the way back.",
                "Correr te hace perder el peligro y el camino de vuelta.",
                "Stop if the ground is falling, on fire, or under traffic.",
                "Para si el piso se cae, hay fuego o hay tráfico.",
                bookPic
            ),
            step(
                "Move to the safest near spot you can see: off the road, out of the water, away from fire.",
                "Muévete al sitio cercano más seguro: fuera del camino, fuera del agua, lejos del fuego.",
                "Walk, do not run. Stay where people can see you.",
                "Camina, no corras. Quédate donde la gente te vea.",
                "The first job is a place that will not hit you.",
                "Lo primero es un lugar que no te golpee.",
                "Stop if moving would put you in the hazard.",
                "Para si moverte te mete en el peligro.",
                bookPic
            ),
        ]
        let body: [FieldStep]
        let care: FieldLoc
        switch family {
        case .bleed:
            body = [
                step(
                    "If you have a cloth, press it hard on the bleeding spot and keep pressing.",
                    "Si tienes un paño, presiónalo fuerte en el sangrado y no lo sueltes.",
                    "Use both hands. Do not peek. Peeking lets the blood out.",
                    "Usa las dos manos. No mires debajo. Mirar deja salir la sangre.",
                    "Pressure is the first move. Looking under the cloth restarts the bleed.",
                    "La presión es el primer movimiento. Mirar debajo reinicia el sangrado.",
                    "Stop if the scene is unsafe. Move them with you if you must.",
                    "Para si la escena es insegura. Muévelos contigo si hace falta.",
                    bleedPic
                ),
                step(
                    "If blood soaks through, put another cloth on top. Do not take the first one off.",
                    "Si la sangre traspasa, pon otro paño encima. No quites el primero.",
                    "Keep pressing. Ask a grown-up to hold if your arms shake.",
                    "Sigue presionando. Pide a un adulto que sostenga si te tiembran los brazos.",
                    "The first cloth is the plug.",
                    "El primer paño es el tapón.",
                    "Stop pressing only if trained help takes over.",
                    "Deja de presionar solo si la ayuda entrenada toma el relevo.",
                    bleedPic
                ),
                step(
                    "Keep them lying down and warm while you press. Do not leave the cloth to go look for a number.",
                    "Mantenlos acostados y calientes mientras presionas. No sueltes el paño para ir a buscar un número.",
                    "Kneel. Both hands on the cloth. Talk to them.",
                    "Arrodíllate. Las dos manos en el paño. Háblales.",
                    "A bleed that waits on a phone starts again.",
                    "Un sangrado que espera un teléfono vuelve a salir.",
                    "Stop if trained help takes the cloth.",
                    "Para si la ayuda entrenada toma el paño.",
                    bleedPic
                ),
            ]
            care = FieldLoc(
                en: "Keep pressure and get to trained help. Do not wait on a number the glass cannot dial.",
                es: "Sigue la presión y llega a ayuda entrenada. No esperes un número que el visor no puede marcar."
            )
        case .cardiac:
            body = [
                step(
                    "Sit them still. Loosen the collar. Do not make them walk or stand to 'get air'.",
                    "Siéntalos quietos. Afloja el cuello. No los hagas caminar ni pararse a 'tomar aire'.",
                    "Sit next to them. Hold their hand. Do not bounce or jog them.",
                    "Siéntate a su lado. Toma su mano. No los sacudas ni los hagas trotar.",
                    "A working heart wants rest. Walking a chest-pain person is how they collapse.",
                    "Un corazón que aún late quiere reposo. Hacer caminar a alguien con dolor de pecho es cómo se caen.",
                    "If they collapse or stop breathing, go to compressions next.",
                    "Si se caen o dejan de respirar, pasa a compresiones.",
                    bookPic
                ),
                step(
                    "Watch the chest. If they collapse or stop normal breathing, start hard fast compressions in the center of the chest.",
                    "Mira el pecho. Si se caen o deja la respiración normal, empieza compresiones fuertes y rápidas al centro.",
                    "Keep other children back. One person pushes.",
                    "Aleja a otros niños. Una persona empuja.",
                    "Chest pain can become no pulse. Delay kills.",
                    "El dolor de pecho puede volverse sin pulso. La demora mata.",
                    "Stop compressions if they cough, move, or breathe normally.",
                    "Para las compresiones si tosen, se mueven o respiran normal.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
                step(
                    "Stay with them. If they collapse again, go back to compressions. Do not leave them alone to 'get help'.",
                    "Quédate. Si se caen otra vez, vuelve a las compresiones. No los dejes solos a 'buscar ayuda'.",
                    "Sit next to them. Watch the chest.",
                    "Siéntate a su lado. Mira el pecho.",
                    "A person left alone with chest pain is the one who dies on the walk for help.",
                    "Quien se queda solo con dolor de pecho es el que muere en el camino a pedir ayuda.",
                    "Stop if trained help takes over.",
                    "Para si la ayuda entrenada toma el relevo.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help. Stay with them. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada. Quédate con ellos. No esperes un número que el visor no puede marcar."
            )
        case .allergy:
            body = [
                step(
                    "If they have their own injector, use it in the outer thigh now. Hold three seconds. Do not wait to see if it 'gets better'.",
                    "Si tienen su inyector, úsalo en el muslo de afuera ya. Sostén tres segundos. No esperes a ver si 'mejora'.",
                    "Take the injector. Orange to the thigh. Click. Hold.",
                    "Toma el inyector. Naranja al muslo. Clic. Sostén.",
                    "The injector is the first move. Waiting is how a throat closes.",
                    "El inyector es el primer movimiento. Esperar es cómo se cierra la garganta.",
                    "If there is no injector, skip to lying them down.",
                    "Si no hay inyector, pasa a acostarlos.",
                    bookPic
                ),
                step(
                    "Lay them down. Legs up if they can breathe. Do not make them walk or stand. Do not put anything in the mouth.",
                    "Acuéstalos. Piernas arriba si pueden respirar. No los hagas caminar ni pararse. No metas nada en la boca.",
                    "Jacket under the legs. Hands off the mouth.",
                    "Chaqueta bajo las piernas. Manos fuera de la boca.",
                    "Walking an allergic person is how they collapse. Back blows are for a block, not a swell.",
                    "Hacer caminar a alguien alérgico es cómo se caen. Los golpes en la espalda son para un bloqueo, no para una hinchazón.",
                    "Sit them up if they cannot breathe lying down.",
                    "Siéntalos si no pueden respirar acostados.",
                    bookPic
                ),
                step(
                    "If they stop breathing, start hard fast compressions in the center of the chest. Stay with them.",
                    "Si dejan de respirar, empieza compresiones fuertes y rápidas al centro del pecho. Quédate.",
                    "Keep other children back. One person pushes.",
                    "Aleja a otros niños. Una persona empuja.",
                    "A closed throat becomes no pulse. Delay kills.",
                    "Una garganta cerrada se vuelve sin pulso. La demora mata.",
                    "Stop compressions if they cough, move, or breathe normally.",
                    "Para las compresiones si tosen, se mueven o respiran normal.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help even if they look better. A second wave can close the throat later.",
                es: "Llega a ayuda entrenada aunque se vean mejor. Una segunda ola puede cerrar la garganta después."
            )
        case .choke:
            body = [
                step(
                    "If they can cough or speak, let them cough. Stay next to them.",
                    "Si pueden toser o hablar, déjalos toser. Quédate a su lado.",
                    "Do not put fingers in their mouth.",
                    "No metas los dedos en la boca.",
                    "Air can still move if they cough.",
                    "El aire aún puede pasar si tosen.",
                    "If they stop coughing and cannot breathe, go to the next move.",
                    "Si dejan de toser y no respiran, pasa al siguiente movimiento.",
                    bookPic
                ),
                step(
                    "If they cannot cough, speak, or breathe, hit their back hard between the shoulders five times.",
                    "Si no pueden toser, hablar ni respirar, golpea la espalda fuerte entre los hombros cinco veces.",
                    "Stand to the side. Aim at the back, not the neck.",
                    "Ponte a un lado. Apunta a la espalda, no al cuello.",
                    "A hard back blow can move the block.",
                    "Un golpe fuerte en la espalda puede mover el bloqueo.",
                    "Stop if they start coughing or breathing.",
                    "Para si empiezan a toser o respirar.",
                    bookPic
                ),
                step(
                    "If the block will not move, wrap your arms around their middle from behind and pull in and up. Then back blows again.",
                    "Si el bloqueo no sale, abraza su medio por detrás y tira adentro y arriba. Luego otra vez golpes en la espalda.",
                    "Stand behind. Fist above the navel. Pull. Do not squeeze the ribs of a small child the same way — keep back blows.",
                    "Ponte detrás. Puño sobre el ombligo. Tira. No aprietes las costillas de un niño igual — sigue con la espalda.",
                    "The second move is for a block that back blows did not shift.",
                    "El segundo movimiento es para un bloqueo que los golpes no movieron.",
                    "Stop if they start coughing or breathing.",
                    "Para si empiezan a toser o respirar.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if the block comes out. They can swell later.",
                es: "Consigue ayuda entrenada aunque salga el bloqueo. Pueden hincharse después."
            )
        case .cpr:
            body = [
                step(
                    "Tap the shoulders and look at the chest for ten seconds. No normal breathing means start compressions.",
                    "Toca los hombros y mira el pecho diez segundos. Sin respiración normal, empieza compresiones.",
                    "Keep other children back. One person pushes. Another watches the child.",
                    "Aleja a otros niños. Una persona empuja. Otra vigila al niño.",
                    "Delay kills. Gasping is not normal breathing.",
                    "La demora mata. El jadeo no es respiración normal.",
                    "If they cough, move, or breathe normally, stop compressions and watch them.",
                    "Si tosen, se mueven o respiran normal, detén y vigílalos.",
                    picture(chapter, prefer: "cpr-check.png")
                ),
                step(
                    "Hard, fast compressions in the center of the chest. Let the chest come back up each time.",
                    "Compresiones fuertes y rápidas al centro del pecho. Deja que el pecho suba cada vez.",
                    "Do not stand on the chest. Do not 'help' with a bounce.",
                    "No te subas al pecho. No 'ayudes' con un rebote.",
                    "Blood has to reach the brain. Shallow pumps do nothing.",
                    "La sangre tiene que llegar al cerebro. Las palmaditas no sirven.",
                    "Stop if an AED is attached and says stay clear, or if they start breathing.",
                    "Para si un DEA dice apartarse o si empiezan a respirar.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
                step(
                    "Keep going. Swap every two minutes if someone else can push. Do not stop to check a pulse with your fingers.",
                    "Sigue. Cambia cada dos minutos si otra persona puede empujar. No pares a buscar pulso con los dedos.",
                    "Count out loud. Then swap. Hands off the neck.",
                    "Cuenta en voz alta. Luego cambia. Manos fuera del cuello.",
                    "A pulse check with untrained fingers wastes the pumps that keep the brain.",
                    "Buscar pulso con dedos sin oficio gasta las bombas que sostienen el cerebro.",
                    "Stop if they breathe or trained help takes over.",
                    "Para si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get trained help and an AED. Keep compressions until they take over.",
                es: "Consigue ayuda entrenada y un DEA. Sigue hasta que tomen el relevo."
            )
        case .drown:
            body = [
                step(
                    "Get them onto land. Throw a branch or cloth. Do not go in if you cannot stand.",
                    "Sácalos a tierra. Lanza una rama o un paño. No entres si no puedes hacer pie.",
                    "Stay on the bank. Hold the cloth. Do not jump in after them.",
                    "Quédate en la orilla. Sostén el paño. No saltes detrás.",
                    "A second drowning starts when a helper goes in over their head.",
                    "Un segundo ahogo empieza cuando el que ayuda entra sin pie.",
                    "Stop if the water is taking you. Get back on land and yell.",
                    "Para si el agua te lleva. Vuelve a tierra y grita.",
                    bookPic
                ),
                step(
                    "On land, tap and look at the chest. No normal breathing means hard fast compressions in the center of the chest.",
                    "En tierra, toca y mira el pecho. Sin respiración normal, compresiones fuertes y rápidas al centro.",
                    "Keep other children back. One person pushes.",
                    "Aleja a otros niños. Una persona empuja.",
                    "Water in the lungs does not change the first move. Blood still has to reach the brain.",
                    "El agua en los pulmones no cambia el primer movimiento. La sangre tiene que llegar al cerebro.",
                    "Roll them if they vomit. Then resume compressions.",
                    "Gíralos si vomitan. Luego reanuda las compresiones.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
                step(
                    "If they start breathing, roll them onto their side and keep them warm. Watch the chest.",
                    "Si empiezan a respirar, gíralos de lado y mantenlos calientes. Mira el pecho.",
                    "Jacket on the trunk. Sit by the head.",
                    "Chaqueta en el tronco. Siéntate junto a la cabeza.",
                    "Water can come back up. The side keeps it out of the airway.",
                    "El agua puede volver. De lado no tapa el aire.",
                    "If the chest stops again, go back to compressions.",
                    "Si el pecho para otra vez, vuelve a las compresiones.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if they cough it out. Water can swell later.",
                es: "Consigue ayuda entrenada aunque tosan el agua. Puede hincharse después."
            )
        case .shock:
            body = [
                step(
                    "Lay them down. Keep them warm. Legs up only if they can breathe and no bone is broken.",
                    "Acuéstalos. Mantenlos calientes. Piernas arriba solo si respiran y no hay hueso roto.",
                    "Cover them with a jacket. Sit by their head.",
                    "Cúbrelos con una chaqueta. Siéntate junto a la cabeza.",
                    "Shock is the body running out of blood or heat. Flat and warm buys time.",
                    "El shock es el cuerpo sin sangre o sin calor. Plano y caliente compra tiempo.",
                    "Sit them up if they cannot breathe lying down.",
                    "Siéntalos si no pueden respirar acostados.",
                    bookPic
                ),
                step(
                    "If they are bleeding, press that first. Do not give food or drink.",
                    "Si sangran, presiónalo primero. No des comida ni bebida.",
                    "Hands on the cloth. Not on a bottle.",
                    "Manos en el paño. No en una botella.",
                    "A drink they cannot swallow is how a shock case chokes.",
                    "Una bebida que no pueden tragar es cómo un shock se ahoga.",
                    "Stop if they vomit — roll them and keep the pressure.",
                    "Para si vomitan — gíralos y sigue la presión.",
                    bleedPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help. Stay with them. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada. Quédate. No esperes un número que el visor no puede marcar."
            )
        case .seizure:
            body = [
                step(
                    "Clear hard things around them. Do not hold them down. Do not put anything in the mouth.",
                    "Quita cosas duras alrededor. No los sujetes. No metas nada en la boca.",
                    "Move rocks and sticks. Hands off their jaw.",
                    "Mueve piedras y palos. Manos fuera de la mandíbula.",
                    "A seized jaw bites a finger. Holding them breaks a bone.",
                    "Una mandíbula en convulsión muerde un dedo. Sujetarlos rompe un hueso.",
                    "Stop if the scene is on fire or in traffic — drag them by the clothes, not the neck.",
                    "Para si hay fuego o tráfico — arrástralos de la ropa, no del cuello.",
                    bookPic
                ),
                step(
                    "Time it. When it stops, roll them onto their side. Stay until they talk sense.",
                    "Mídele el tiempo. Cuando pare, gíralos de lado. Quédate hasta que hablen con sentido.",
                    "Count out loud. Then roll. Then sit with them.",
                    "Cuenta en voz alta. Luego gira. Luego siéntate con ellos.",
                    "The side keeps the tongue and spit out of the airway.",
                    "De lado la lengua y la saliva no tapan el aire.",
                    "If it lasts longer than they can stay pink, get to care now.",
                    "Si dura más de lo que pueden seguir rosados, busca cuidado ya.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help after any first seizure, or any that repeats. Stay on their side.",
                es: "Llega a ayuda entrenada después de la primera convulsión o si se repite. Sigue de lado."
            )
        case .burn:
            body = [
                step(
                    "Get the heat off. Cool the burn with clean water. Do not put ice, butter, or toothpaste on it.",
                    "Quita el calor. Enfría la quemadura con agua limpia. No pongas hielo, mantequilla ni pasta.",
                    "Hold the water on the skin. Do not smear anything on it.",
                    "Sostén el agua en la piel. No untes nada.",
                    "Ice and grease hold heat in.",
                    "El hielo y la grasa guardan el calor.",
                    "Stop cooling if they start to shake from cold.",
                    "Deja de enfriar si empiezan a temblar de frío.",
                    bookPic
                ),
                step(
                    "Cover loosely with a clean cloth. Do not pop blisters.",
                    "Cubre flojo con un paño limpio. No revientes ampollas.",
                    "Touch the cloth, not the burn.",
                    "Toca el paño, no la quemadura.",
                    "Open skin is how dirt gets in.",
                    "La piel abierta es por donde entra suciedad.",
                    "Stop if the cloth sticks — leave it and get care.",
                    "Para si el paño se pega — déjalo y busca cuidado.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help for any burn that is big, on the face, or on the hands.",
                es: "Llega a ayuda entrenada si la quemadura es grande, en la cara o en las manos."
            )
        case .heat:
            body = [
                step(
                    "Get them to shade. Strip extra layers. Pour water on the skin and fan.",
                    "Llévalos a la sombra. Quita capas de más. Echa agua en la piel y abanica.",
                    "Hold the water bottle. Fan with a hat or cloth.",
                    "Sostén la botella. Abanica con un sombrero o un paño.",
                    "A body that cannot dump heat cooks the brain.",
                    "Un cuerpo que no suelta calor cocina el cerebro.",
                    "Stop if they start to shake from cold — dry them and shade only.",
                    "Para si tiemblan de frío — sécalos y solo sombra.",
                    bookPic
                ),
                step(
                    "Sips of treated water if they can swallow. Do not force a drink. Rest until they talk sense.",
                    "Sorbos de agua tratada si pueden tragar. No fuerces la bebida. Descansa hasta que hablen con sentido.",
                    "Hold the cup. Do not pour it down.",
                    "Sostén el vaso. No lo viertas.",
                    "A confused swallow is how heat becomes a choke.",
                    "Un trago confuso es cómo el calor se vuelve un ahogo.",
                    "If they stop sweating and stop making sense, carry them to care.",
                    "Si dejan de sudar y de tener sentido, llévalos a cuidado.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help for confusion, no sweat, or a person who will not wake. Shade on the way.",
                es: "Llega a ayuda entrenada si hay confusión, no sudan o no despiertan. Sombra en el camino."
            )
        case .cold:
            body = [
                step(
                    "Stop walking into wind. Change out of wet next-to-skin layers. Put the dry layer on the trunk first.",
                    "Deja de caminar contra el viento. Cambia lo mojado pegado a la piel. La capa seca va al tronco primero.",
                    "Hands on the wet shirt. Pull it off. Dry shirt on.",
                    "Manos en la camisa mojada. Quítala. Pon la seca.",
                    "Wet cotton on the trunk is how a walk becomes a collapse.",
                    "Algodón mojado en el tronco es cómo un caminar se vuelve un colapso.",
                    "Stop if they cannot stand — sit, pad the ground, yell.",
                    "Para si no pueden sostenerse — siéntate, acolcha el piso, grita.",
                    bookPic
                ),
                step(
                    "Share a dry bag or jacket. Skin-to-skin on the trunk if you have no dry layer. No alcohol.",
                    "Comparte una bolsa o chaqueta seca. Piel con piel en el tronco si no hay capa seca. Sin alcohol.",
                    "Hug the trunk, not the hands. Hands last.",
                    "Abraza el tronco, no las manos. Las manos al último.",
                    "Alcohol opens the skin and dumps the last heat.",
                    "El alcohol abre la piel y tira el último calor.",
                    "Stop if they stop shivering and stop making sense — carry them.",
                    "Para si dejan de temblar y de tener sentido — llévalos.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help for confusion or a person who stopped shivering. Keep them dry on the way.",
                es: "Llega a ayuda entrenada si hay confusión o dejaron de temblar. Sigue seco en el camino."
            )
        case .flood:
            body = [
                step(
                    "If you hear it, see it rise, or the sky up-canyon is a wall — out of the wash now. High ground.",
                    "Si lo oyes, lo ves subir o el cielo río arriba es una pared — sal del cauce ya. Tierra alta.",
                    "Walk up the bank. Do not cross. Do not grab a stick in the flow.",
                    "Sube la orilla. No cruces. No agarres un palo en la corriente.",
                    "A wall of water moves faster than a child can run down-canyon.",
                    "Una pared de agua corre más que un niño río abajo.",
                    "Stop if the bank is falling — crawl, do not stand on undercut dirt.",
                    "Para si la orilla se cae — gatea, no te pares en tierra socavada.",
                    bookPic
                ),
                step(
                    "Stay on the high spot until the water drops. Signal from there. Do not drive or wade it.",
                    "Quédate en lo alto hasta que baje. Señala desde ahí. No conduzcas ni vadees.",
                    "Sit. Wave a cloth. Yell in threes.",
                    "Siéntate. Agita un paño. Grita de a tres.",
                    "Most flood deaths are the second trip into the water.",
                    "La mayoría de muertes en crecida son el segundo viaje al agua.",
                    "Move only if fire or night cold will hit you on that rock.",
                    "Muévete solo si el fuego o el frío de noche te van a pegar en esa roca.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay high until a known voice reaches you. Do not follow a stranger back into the wash.",
                es: "Quédate alto hasta que una voz conocida te alcance. No sigas a un extraño de vuelta al cauce."
            )
        case .lightning:
            body = [
                step(
                    "Off peaks, towers, fence lines, and lone trees. Drop poles and long conductors. Crouch on your pack if you cannot get lower.",
                    "Baja de picos, torres, cercas y árboles solos. Suelta postes y cables. Agáchate en la mochila si no puedes bajar más.",
                    "Squat. Feet together. Hands off the ground.",
                    "Agáchate. Pies juntos. Manos fuera del piso.",
                    "A lone tall thing is the rod. You do not want to be the rod.",
                    "Una cosa alta y sola es el pararrayos. No quieres serlo.",
                    "Stop if you can get inside a closed car or a real building — that wins.",
                    "Para si puedes entrar a un auto cerrado o un edificio de verdad — eso gana.",
                    bookPic
                ),
                step(
                    "Wait until thirty minutes after the last thunder. Then move to visible ground.",
                    "Espera treinta minutos después del último trueno. Luego muévete a tierra visible.",
                    "Count. Then walk. Then yell.",
                    "Cuenta. Luego camina. Luego grita.",
                    "A second cell often sits behind the first.",
                    "A menudo hay otra celda detrás de la primera.",
                    "If someone is hit, they are safe to touch. Start compressions if they are not breathing.",
                    "Si a alguien le cae, se le puede tocar. Empieza compresiones si no respiran.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help after any strike. Burns and hearts fail later.",
                es: "Llega a ayuda entrenada después de cualquier impacto. Quemaduras y corazones fallan después."
            )
        case .tornado:
            body = [
                step(
                    "Get low. A ditch or the lowest room. Not under a lone tree. Cover the head.",
                    "Ponte bajo. Una zanja o el cuarto más bajo. No bajo un árbol solo. Cubre la cabeza.",
                    "Lie down. Hands on the head. Cloth over the face if dirt flies.",
                    "Acuéstate. Manos en la cabeza. Un paño en la cara si vuela tierra.",
                    "Flying wood kills more than the wind.",
                    "La madera que vuela mata más que el viento.",
                    "Stop if a wall is coming down — crawl to the open ditch.",
                    "Para si un muro se cae — gatea a la zanja abierta.",
                    bookPic
                ),
                step(
                    "Stay down until the wind has been quiet. Then move to visible ground and yell in threes.",
                    "Quédate abajo hasta que el viento esté quieto. Luego muévete a tierra visible y grita de a tres.",
                    "Listen. Then stand. Then three yells.",
                    "Escucha. Luego párate. Luego tres gritos.",
                    "A second cell can sit behind a quiet minute.",
                    "Otra celda puede venir detrás de un minuto quieto.",
                    "Move only if fire or flood will hit you in that ditch.",
                    "Muévete solo si el fuego o la crecida te van a pegar en esa zanja.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay put until a known voice reaches you. Do not walk a debris field alone.",
                es: "Quédate hasta que una voz conocida te alcance. No camines solo entre escombros."
            )
        case .fracture:
            body = [
                step(
                    "Do not try to push a bone back. Leave the limb how it lies.",
                    "No intentes meter un hueso. Deja el miembro como está.",
                    "Hands off the break. Hold the rest of the body still.",
                    "Manos fuera de la fractura. Sostén el resto del cuerpo quieto.",
                    "Moving the bone can cut the rest of the limb.",
                    "Mover el hueso puede cortar el resto del miembro.",
                    "Stop if they faint or the fingers go white and cold.",
                    "Para si se desmayan o los dedos se ponen blancos y fríos.",
                    bookPic
                ),
                step(
                    "Pad around the limb with cloth and tie it to something stiff so it cannot flop. Tie loose enough to slip a finger under.",
                    "Acolcha el miembro con tela y átalo a algo rígido para que no se mueva. Lo bastante flojo para meter un dedo.",
                    "Hold the stick. Let a grown-up tie if they are there.",
                    "Sostén el palo. Deja que un adulto ate si está ahí.",
                    "A floppy break keeps tearing.",
                    "Una fractura suelta sigue rasgando.",
                    "Stop if the tie makes fingers numb or blue.",
                    "Para si el nudo deja los dedos entumecidos o azules.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Carry them if you can. Get to trained help. Do not wait on a number the glass cannot dial.",
                es: "Cárgalos si puedes. Llega a ayuda entrenada. No esperes un número que el visor no puede marcar."
            )
        case .lost:
            body = [
                step(
                    "Stay where you are if that spot is safe. Hug a tree or sit on a rock people can see.",
                    "Quédate si el sitio es seguro. Abraza un árbol o siéntate en una roca visible.",
                    "Sit. Do not wander to 'look for camp'.",
                    "Siéntate. No deambules a 'buscar el campamento'.",
                    "Searchers walk a line. A moving child is the one they miss.",
                    "Los buscadores caminan una línea. Un niño que se mueve es el que pierden.",
                    "Move only if fire, water, or night cold will hit you here.",
                    "Muévete solo si el fuego, el agua o el frío de noche te van a pegar aquí.",
                    bookPic
                ),
                step(
                    "Make yourself big and loud from that spot: yell in threes, wave a bright cloth.",
                    "Hazte grande y ruidoso desde ese sitio: grita de a tres, agita un paño brillante.",
                    "Three yells. Then listen. Then three more.",
                    "Tres gritos. Luego escucha. Luego tres más.",
                    "A pattern is how people know you are a person.",
                    "Un patrón es cómo saben que eres una persona.",
                    "Stop yelling if you need that breath to stay warm.",
                    "Deja de gritar si necesitas ese aire para no enfriar.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay put until a known voice reaches you. Do not follow a stranger off your spot.",
                es: "Quédate hasta que una voz conocida te alcance. No sigas a un extraño fuera de tu sitio."
            )
        case .eye:
            body = [
                step(
                    "Do not rub. Rinse with clean water from the inside corner out.",
                    "No frotes. Enjuaga con agua limpia del lagrimal hacia afuera.",
                    "Hold the water. Tilt the head. Do not poke.",
                    "Sostén el agua. Inclina la cabeza. No pinches.",
                    "Rubbing scratches the eye. A rinse can float the speck out.",
                    "Frotar raya el ojo. Un enjuague puede sacar la mota.",
                    "Stop if the eye is cut or the pupil looks wrong — cover loose and go.",
                    "Para si el ojo está cortado o la pupila se ve rara — cubre flojo y vete.",
                    bookPic
                ),
                step(
                    "Cover loose with a clean cloth. Do not tape the eye shut.",
                    "Cubre flojo con un paño limpio. No tapes el ojo cerrado.",
                    "Touch the cloth, not the eye.",
                    "Toca el paño, no el ojo.",
                    "Pressure on a hurt eye makes it worse.",
                    "La presión en un ojo herido lo empeora.",
                    "Stop if they cannot see or the pain grows — get to care.",
                    "Para si no ven o el dolor crece — busca cuidado.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help if it still hurts or they cannot see. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada si aún duele o no ven. No esperes un número que el visor no puede marcar."
            )
        case .nose:
            body = [
                step(
                    "Sit up. Lean forward. Pinch the soft part of the nose. Do not tip the head back.",
                    "Siéntate. Inclínate adelante. Pellizca la parte blanda de la nariz. No eches la cabeza atrás.",
                    "Pinch. Lean. Breathe through the mouth.",
                    "Pellizca. Inclínate. Respira por la boca.",
                    "Head back dumps blood into the throat. Forward lets it out.",
                    "La cabeza atrás tira sangre a la garganta. Adelante la saca.",
                    "Stop if they faint or the blood will not slow — press and get care.",
                    "Para si se desmayan o la sangre no afloja — aprieta y busca cuidado.",
                    bookPic
                ),
                step(
                    "Spit blood out. Keep the pinch for a full ten minutes. Do not pack the nose with tissue.",
                    "Escupe la sangre. Sigue el pellizco diez minutos enteros. No rellenes la nariz con papel.",
                    "Hold the pinch. Count. Spit.",
                    "Sostén el pellizco. Cuenta. Escupe.",
                    "A tissue plug is how a nosebleed becomes a choke.",
                    "Un tapón de papel es cómo una hemorragia nasal se ahoga.",
                    "Stop if they cannot breathe through the mouth.",
                    "Para si no pueden respirar por la boca.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help if it will not stop or they feel faint. Sit forward on the way.",
                es: "Llega a ayuda entrenada si no para o se marean. Adelante en el camino."
            )
        case .animal:
            body = [
                step(
                    "Give it the road or the brush. Do not run. Back out slow. Pick up a small child.",
                    "Dale el camino o el monte. No corras. Retrocede lento. Carga a un niño pequeño.",
                    "Stand still. Then step back. Hands on a child, not a stick at the animal.",
                    "Quédate quieto. Luego un paso atrás. Manos en el niño, no un palo al animal.",
                    "A charge starts when you corner it or you run like prey.",
                    "La carga empieza cuando lo acorralas o corres como presa.",
                    "Stop if it is already on someone — get space, then the bite card.",
                    "Para si ya está encima de alguien — abre espacio, luego la tarjeta de mordedura.",
                    bookPic
                ),
                step(
                    "Once it has the space, stay in a group and leave the way you came. Do not feed it. Do not get between adults and young.",
                    "Cuando tenga el espacio, quédate en grupo y sal por donde viniste. No lo alimentes. No te metas entre adultos y crías.",
                    "Walk with the party. Hands off food.",
                    "Camina con el grupo. Manos fuera de la comida.",
                    "Food on you is why it follows.",
                    "La comida encima es por qué te sigue.",
                    "If it bit, wash, still the person, and get to care. No ice, no cut, no suck.",
                    "Si mordió, lava, quieto, y busca cuidado. Sin hielo, sin corte, sin chupar.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help after any bite. Stay with the party. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada después de cualquier mordedura. Quédate con el grupo. No esperes un número que el visor no puede marcar."
            )
        case .stroke:
            body = [
                step(
                    "Sit them still. Note the time. One side of the face, one arm, or speech gone wrong is enough.",
                    "Siéntalos quietos. Anota la hora. Un lado de la cara, un brazo o el habla rara basta.",
                    "Sit next to them. Look at the face. Say the time out loud.",
                    "Siéntate a su lado. Mira la cara. Di la hora en voz alta.",
                    "Time is the drug. Walking a stroke off is how the brain keeps dying.",
                    "El tiempo es el fármaco. Hacer caminar un derrame es cómo el cerebro sigue muriendo.",
                    "If they collapse or stop breathing, go to compressions.",
                    "Si se caen o dejan de respirar, pasa a compresiones.",
                    bookPic
                ),
                step(
                    "Do not give food, drink, or pills. Do not make them walk. Keep them sitting or lying with the head a little up.",
                    "No des comida, bebida ni pastillas. No los hagas caminar. Manténlos sentados o acostados con la cabeza un poco alta.",
                    "Hands off the bottle and the pills. Hold their hand.",
                    "Manos fuera de la botella y las pastillas. Toma su mano.",
                    "A swallow they cannot control is how a stroke becomes a choke.",
                    "Un trago que no controlan es cómo un derrame se ahoga.",
                    "If they vomit, roll them onto the weak side.",
                    "Si vomitan, gíralos hacia el lado débil.",
                    bookPic
                ),
                step(
                    "Stay with them. If they stop breathing, start hard fast compressions in the center of the chest.",
                    "Quédate. Si dejan de respirar, empieza compresiones fuertes y rápidas al centro del pecho.",
                    "Watch the chest. One person pushes if it stops.",
                    "Mira el pecho. Una persona empuja si para.",
                    "A stroke can become no pulse. Delay kills.",
                    "Un derrame puede volverse sin pulso. La demora mata.",
                    "Stop compressions if they breathe or trained help takes over.",
                    "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help now. Say the time it started. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada ya. Di la hora en que empezó. No esperes un número que el visor no puede marcar."
            )
        case .head:
            body = [
                step(
                    "If they fell or were hit, do not move the neck. Keep the head in line with the back.",
                    "Si se cayeron o los golpearon, no muevas el cuello. La cabeza en línea con la espalda.",
                    "Hands on the ears. Hold the head still. Do not twist.",
                    "Manos en las orejas. Sostén la cabeza quieta. No gires.",
                    "A broken neck can cut the rest of the body when you sit them up.",
                    "Un cuello roto puede cortar el resto del cuerpo si los sientas.",
                    "Move them only if fire, water, or traffic will hit them here.",
                    "Muévelos solo si el fuego, el agua o el tráfico los va a pegar aquí.",
                    bookPic
                ),
                step(
                    "Watch the chest. If they vomit, roll the whole body as one piece. Do not stuff a wound in the scalp.",
                    "Mira el pecho. Si vomitan, gira el cuerpo entero de una pieza. No rellenes una herida en el cuero.",
                    "Hold the head. Let someone else roll the hips.",
                    "Sostén la cabeza. Que otro gire las caderas.",
                    "Stuffing a scalp wound hides a bleed you still have to press.",
                    "Rellenar el cuero esconde un sangrado que aún hay que presionar.",
                    "If they stop breathing, start compressions and keep the neck still.",
                    "Si dejan de respirar, empieza compresiones y sigue el cuello quieto.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help after any knock-out or a head that will not stop bleeding. Keep the neck still on the way.",
                es: "Llega a ayuda entrenada si se desmayaron o la cabeza no para de sangrar. Cuello quieto en el camino."
            )
        case .poison:
            body = [
                step(
                    "Take the bottle or plant away. Do not make them vomit. Do not give milk or salt water.",
                    "Quita la botella o la planta. No los hagas vomitar. No des leche ni agua con sal.",
                    "Hands on the bottle. Not on their throat.",
                    "Manos en la botella. No en su garganta.",
                    "Forced vomit burns the throat twice and can choke them.",
                    "El vómito forzado quema la garganta dos veces y puede ahogarlos.",
                    "If they are already vomiting, roll them and keep the bottle.",
                    "Si ya vomitan, gíralos y quédate con la botella.",
                    bookPic
                ),
                step(
                    "Rinse the mouth with clean water. If it is on the skin, water for fifteen minutes. Keep the container.",
                    "Enjuaga la boca con agua limpia. Si está en la piel, agua quince minutos. Quédate con el envase.",
                    "Hold the water. Tilt. Spit. Do not swallow the rinse.",
                    "Sostén el agua. Inclina. Escupe. No tragues el enjuague.",
                    "The label is what trained help reads. The rinse is what stops more going in.",
                    "La etiqueta es lo que lee la ayuda. El enjuague es lo que para más entrada.",
                    "Stop rinsing if they cannot swallow or cannot stay awake.",
                    "Para el enjuague si no pueden tragar o no se mantienen despiertos.",
                    bookPic
                ),
                step(
                    "If they stop breathing, start hard fast compressions. Stay with them and the container.",
                    "Si dejan de respirar, empieza compresiones fuertes y rápidas. Quédate con ellos y el envase.",
                    "One person pushes. Another holds the bottle.",
                    "Una persona empuja. Otra sostiene la botella.",
                    "A swallowed poison can stop the chest. The bottle still has to go with them.",
                    "Un veneno tragado puede parar el pecho. La botella tiene que ir con ellos.",
                    "Stop compressions if they breathe or trained help takes over.",
                    "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help with the container. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada con el envase. No esperes un número que el visor no puede marcar."
            )
        case .asthma:
            body = [
                step(
                    "Sit them up. Their own inhaler, two puffs, then wait. Do not make them lie flat or walk.",
                    "Siéntalos. Su inhalador, dos puff, luego espera. No los acuestes ni los hagas caminar.",
                    "Shake the inhaler. One puff. Breathe. Then the second.",
                    "Agita el inhalador. Un puff. Respira. Luego el segundo.",
                    "Flat and walking both steal the air they have left.",
                    "Acostados y caminando les roban el aire que les queda.",
                    "If there is no inhaler, keep them sitting and go to the next move.",
                    "Si no hay inhalador, síguelos sentados y pasa al siguiente.",
                    bookPic
                ),
                step(
                    "If they cannot speak a full sentence, stay sitting and get to care. Watch the chest.",
                    "Si no pueden decir una frase entera, sigue sentado y busca cuidado. Mira el pecho.",
                    "Sit behind them. Hands on their shoulders. Count breaths out loud.",
                    "Siéntate detrás. Manos en los hombros. Cuenta las respiraciones.",
                    "A silent chest is the danger, not the wheeze.",
                    "El peligro es el pecho silencioso, no el silbido.",
                    "If the chest stops, start compressions.",
                    "Si el pecho para, empieza compresiones.",
                    bookPic
                ),
                step(
                    "If they stop breathing, start hard fast compressions in the center of the chest. Stay sitting them up until then.",
                    "Si dejan de respirar, empieza compresiones fuertes y rápidas al centro. Hasta entonces síguelos sentados.",
                    "Keep other children back. One person pushes.",
                    "Aleja a otros niños. Una persona empuja.",
                    "An empty inhaler does not change the first move when the chest stops.",
                    "Un inhalador vacío no cambia el primer movimiento cuando el pecho para.",
                    "Stop compressions if they breathe or trained help takes over.",
                    "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help if two puffs do not open the chest. Sit them on the way.",
                es: "Llega a ayuda entrenada si dos puff no abren el pecho. Siéntalos en el camino."
            )
        case .avalanche:
            body = [
                step(
                    "Mark the last place you saw them. Dig from downhill of that mark, not from below the pile.",
                    "Marca el último sitio donde los viste. Cava río abajo de esa marca, no desde abajo del montón.",
                    "Plant a stick at the last-seen. Dig toward it, not under it.",
                    "Clava un palo en el último visto. Cava hacia él, no debajo.",
                    "Digging from below drops more snow on the face.",
                    "Cavar desde abajo tira más nieve a la cara.",
                    "Stop if a second slide is coming — get off the slope, then come back.",
                    "Para si viene otra placa — sal de la pendiente, luego vuelve.",
                    bookPic
                ),
                step(
                    "Clear the face first. Then the chest. Then get them onto something dry.",
                    "Limpia la cara primero. Luego el pecho. Luego ponlos en algo seco.",
                    "Hands at the mouth. Then the chest. Then drag onto a pack.",
                    "Manos en la boca. Luego el pecho. Luego arrastra a una mochila.",
                    "Air is the first minute. Wet snow on the trunk is the second death.",
                    "El aire es el primer minuto. Nieve mojada en el tronco es la segunda muerte.",
                    "If they are not breathing on the dry spot, start compressions.",
                    "Si no respiran en el sitio seco, empieza compresiones.",
                    bookPic
                ),
                step(
                    "On dry ground, tap and look at the chest. No normal breathing means hard fast compressions.",
                    "En tierra seca, toca y mira el pecho. Sin respiración normal, compresiones fuertes y rápidas.",
                    "Keep other children back. One person pushes.",
                    "Aleja a otros niños. Una persona empuja.",
                    "Snow in the lungs does not change the first move. Blood still has to reach the brain.",
                    "La nieve en los pulmones no cambia el primer movimiento. La sangre tiene que llegar al cerebro.",
                    "Stop if they breathe or trained help takes over.",
                    "Para si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png")
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help even if they cough it out. Stay dry and visible.",
                es: "Llega a ayuda entrenada aunque tosan la nieve. Sigue seco y visible."
            )
        case .rip:
            body = [
                step(
                    "Do not swim against the current. Float. Face the beach. Wave.",
                    "No nades contra la corriente. Flota. Mira la playa. Saluda.",
                    "On your back. Hand up. Do not fight the pull.",
                    "De espaldas. Mano arriba. No pelees el tiro.",
                    "A rip is a conveyor. Fighting it is how you empty the tank.",
                    "Una resaca es una cinta. Pelearla es cómo se acaba el aire.",
                    "If you can stand, walk out to the side, not straight in.",
                    "Si haces pie, sal de lado, no derecho.",
                    bookPic
                ),
                step(
                    "Swim parallel to the beach until the pull lets go, then in. Do not aim at the place you left.",
                    "Nada paralelo a la playa hasta que suelte, luego hacia adentro. No apuntes al sitio de donde saliste.",
                    "Look down the beach. Swim that way. Then in.",
                    "Mira a lo largo de la playa. Nada ahí. Luego hacia adentro.",
                    "The rip is a narrow river. Sideways is out of it.",
                    "La resaca es un río estrecho. De lado sales.",
                    "If you cannot swim, keep floating and waving until a throw-line reaches you.",
                    "Si no sabes nadar, sigue flotando y saludando hasta que llegue una cuerda.",
                    bookPic
                ),
                step(
                    "Once you can stand, walk out. Do not go back in for a board or a bag. Yell in threes from the sand.",
                    "Cuando hagas pie, sal. No vuelvas por una tabla o una bolsa. Grita de a tres desde la arena.",
                    "Walk. Then sit. Then three yells.",
                    "Camina. Luego siéntate. Luego tres gritos.",
                    "Most second drownings are the trip back for gear.",
                    "La mayoría de los segundos ahogos son el viaje de vuelta por el equipo.",
                    "If someone else is still in it, throw a branch or cloth. Do not go in if you cannot stand.",
                    "Si alguien más sigue adentro, lanza una rama o un paño. No entres si no haces pie.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay on the sand until a known voice reaches you. Do not go back in.",
                es: "Quédate en la arena hasta que una voz conocida te alcance. No vuelvas al agua."
            )
        case .start:
            body = [
                step(
                    "If someone is hurt: stop bleeding or start breaths first. If no one is hurt, stay visible and stay with the party.",
                    "Si alguien está herido: para el sangrado o empieza respiraciones primero. Si nadie está herido, quédate visible y con el grupo.",
                    "Look at the person. Then one hand move. Then tap NEXT.",
                    "Mira a la persona. Luego un movimiento. Luego toca NEXT.",
                    "The first job is the thing that is killing them. Stacking jobs skips that.",
                    "Lo primero es lo que los está matando. Apilar tareas se salta eso.",
                    "Stop if you cannot see, cannot stand, or cannot hear.",
                    "Para si no ves, no te sostienes o no oyes.",
                    bookPic
                ),
                step(
                    "From that spot, yell in threes and wave a bright cloth. Do not wander. Do not eat wild plants. Do not drink untreated water.",
                    "Desde ese sitio, grita de a tres y agita un paño brillante. No deambules. No comas plantas silvestres. No bebas agua sin tratar.",
                    "Three yells. Then sit. Hands off plants and standing water.",
                    "Tres gritos. Luego siéntate. Manos fuera de plantas y agua estancada.",
                    "Searchers walk a line. Unknown plants and untreated water make two problems.",
                    "Los buscadores caminan una línea. Plantas desconocidas y agua sin tratar hacen dos problemas.",
                    "Stop if you feel faint. Sit. Yell.",
                    "Para si te desmayas. Siéntate. Grita.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to people who can help. Stay with the party. Do not wait on a number the glass cannot dial.",
                es: "Llega a gente que pueda ayudar. Quédate con el grupo. No esperes un número que el visor no puede marcar."
            )
        }
        let finish = [
            step(
                "If you cannot finish, stay visible and stay with the party. Do not eat wild plants. Do not drink untreated water.",
                "Si no puedes terminar, quédate visible y con el grupo. No comas plantas silvestres. No bebas agua sin tratar.",
                "Hands off plants and standing water. Sit where people can see you.",
                "Manos fuera de plantas y agua estancada. Siéntate donde te vean.",
                "Unknown plants and untreated water are how a small problem becomes two.",
                "Plantas desconocidas y agua sin tratar convierten un problema en dos.",
                "Stop if you feel faint. Sit. Yell.",
                "Para si te desmayas. Siéntate. Grita.",
                bookPic
            ),
        ]
        var steps = start + body + finish
        if steps.count > 8 { steps = Array(steps.prefix(8)) }
        let titleText = asked.isEmpty ? "ASK" : String(asked.prefix(44))
        _ = locale
        return FieldCard(
            schema: "1.4",
            id: FieldAsk.liveID,
            category: "ask",
            states: ["TX", "NM"],
            title: FieldLoc(en: titleText, es: titleText),
            situation: FieldLoc(
                en: "You asked: \(asked). First time. One move per step. A child can follow it.",
                es: "Preguntaste: \(asked). Primera vez. Un movimiento por paso. Un niño puede seguirlo."
            ),
            stop_if: [
                FieldLoc(
                    en: "Stop if the place is on fire, collapsing, or in traffic.",
                    es: "Para si hay fuego, derrumbe o tráfico."
                ),
                FieldLoc(
                    en: "Stop if they stop breathing, or bleeding soaks through and you cannot keep pressure.",
                    es: "Para si dejan de respirar, o el sangrado traspasa y no puedes mantener presión."
                ),
            ],
            get_to_care: care,
            speak: true,
            sendToParty: false,
            steps: steps,
            packs: packId.map { [$0] }
        )
    }

    private static func picture(_ chapter: [FieldCard], prefer: String? = nil) -> String {
        var names: [String] = []
        for card in chapter {
            for st in card.steps where !st.image.isEmpty {
                names.append(st.image)
            }
        }
        if let prefer, names.contains(prefer) { return prefer }
        return names.first ?? "bleed-pack.png"
    }

    private static func step(
        _ doEn: String, _ doEs: String,
        _ childEn: String, _ childEs: String,
        _ whyEn: String, _ whyEs: String,
        _ stopEn: String, _ stopEs: String,
        _ image: String
    ) -> FieldStep {
        FieldStep(
            do: FieldLoc(en: doEn, es: doEs),
            why: FieldLoc(en: whyEn, es: whyEs),
            child: FieldLoc(en: childEn, es: childEs),
            stop: FieldLoc(en: stopEn, es: stopEs),
            image: image
        )
    }
}
