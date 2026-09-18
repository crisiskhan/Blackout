import Foundation
import FieldCorpus

/// Offline first-time walks when the packed book has no hit.
/// Life-threat families start on the move that stops dying. Airplane only.
public enum FieldAskWalk {
    public enum Family: String, Sendable {
        case bleed, cardiac, allergy, choke, cpr, drown, shock, seizure
        case burn, heat, cold, flood, lightning, tornado
        case fracture, lost, eye, nose, animal
        case stroke, head, poison, asthma, avalanche, rip
        case breath, hurt, sick, stay, start
        case infant, selfChoke, pregnant, hole, sugar, overdose, tight, stuck
    }

    public static func family(for tokens: Set<String>) -> Family {
        if !tokens.isDisjoint(with: ["infant", "baby", "newborn"])
            && !tokens.isDisjoint(with: [
                "choke", "choking", "airway", "cpr",
                "unresponsive", "unconscious", "collapsed", "fainted", "selfchoke",
            ])
        {
            return .infant
        }
        if !tokens.isDisjoint(with: ["selfchoke"]) {
            return .selfChoke
        }
        if !tokens.isDisjoint(with: ["pregnant", "pregnancy"])
            && !tokens.isDisjoint(with: [
                "choke", "choking", "airway", "cpr",
                "unresponsive", "unconscious", "collapsed", "fainted",
            ])
        {
            return .pregnant
        }
        if !tokens.isDisjoint(with: ["sucking"])
            || (
                !tokens.isDisjoint(with: ["hole", "puncture"])
                    && tokens.contains("chest")
            )
        {
            return .hole
        }
        if tokens.contains("impaled")
            || (
                tokens.contains("stuck")
                    && !tokens.isDisjoint(with: ["wound", "bleed", "chest"])
                    && tokens.isDisjoint(with: ["food", "throat", "choke"])
            )
        {
            return .stuck
        }
        if !tokens.isDisjoint(with: ["sugar", "diabetic", "glucose"]) {
            return .sugar
        }
        if !tokens.isDisjoint(with: ["overdose", "narcan", "fentanyl", "opioid"]) {
            return .overdose
        }
        if !tokens.isDisjoint(with: ["tourniquet", "windlass"]) {
            return .tight
        }
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
        if !tokens.isDisjoint(with: ["breath", "breathe"]) {
            return .breath
        }
        if !tokens.isDisjoint(with: ["hurt", "injured", "injury"]) {
            return .hurt
        }
        if !tokens.isDisjoint(with: ["sick", "ill"]) {
            return .sick
        }
        if !tokens.isDisjoint(with: ["stay", "stable"]) {
            return .stay
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
            .breath, .hurt, .stay,
            .infant, .selfChoke, .pregnant, .hole, .sugar, .overdose, .tight, .stuck,
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
                    "Expose the wound. Feed a cloth straight into the hole. Press hard with both hands. Do not peek.",
                    "Expón la herida. Mete un paño en el hueco. Presiona con las dos manos. No mires debajo.",
                    "Say: I am pressing. It will hurt. That means it is working. Both hands. Do not lift.",
                    "Di: estoy presionando. Va a doler. Eso significa que funciona. Las dos manos. No levantes.",
                    "Surface wipes do not close a vessel. Looking under the cloth restarts the bleed.",
                    "Limpiar la superficie no cierra un vaso. Mirar debajo reinicia el sangrado.",
                    "If a limb still pours, tap TIGHT. If the chest sucks air, tap HOLE. If something is still in it, tap STUCK.",
                    "Si una extremidad chorrea, toca TIGHT. Si el pecho chupa aire, toca HOLE. Si algo sigue adentro, toca STUCK.",
                    bleedPic
                ),
                step(
                    "If blood soaks through, put another cloth on top. Do not take the first one off.",
                    "Si la sangre traspasa, pon otro paño encima. No quites el primero.",
                    "Say: keep the first cloth. Add another. Keep pressing.",
                    "Di: deja el primero. Pon otro. Sigue presionando.",
                    "The first cloth is the plug.",
                    "El primer paño es el tapón.",
                    "Stop pressing only if trained help takes over.",
                    "Deja de presionar solo si la ayuda entrenada toma el relevo.",
                    bleedPic
                ),
                step(
                    "Keep them lying down and warm while you press. No food. No drink. Watch the chest.",
                    "Mantenlos acostados y calientes mientras presionas. Sin comida. Sin bebida. Mira el pecho.",
                    "Say: stay down. I will not leave. Kneel. Both hands on the cloth.",
                    "Di: quédate abajo. No me voy. Arrodíllate. Las dos manos en el paño.",
                    "A bleed that waits on a phone starts again. A drink they cannot swallow is a choke.",
                    "Un sangrado que espera un teléfono vuelve. Una bebida que no tragan es un ahogo.",
                    "If they fade or the chest stops, tap CPR. Pale and cold: tap SHOCK.",
                    "Si se apagan o el pecho para, toca CPR. Pálido y frío: toca SHOCK.",
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
                    "If they have their own injector, use it in the outer thigh now. Hold three seconds. Do not wait to see if it 'gets better'. A second injector after five minutes if they have one and they are still swelling.",
                    "Si tienen su inyector, úsalo en el muslo de afuera ya. Sostén tres segundos. No esperes a ver si 'mejora'. Un segundo a los cinco minutos si tienen otro y siguen hinchando.",
                    "Say: orange to the thigh. Click. Hold. Count three. Then lie them down.",
                    "Di: naranja al muslo. Clic. Sostén. Cuenta tres. Luego acuéstalos.",
                    "The injector is the first move. Waiting is how a throat closes.",
                    "El inyector es el primer movimiento. Esperar es cómo se cierra la garganta.",
                    "If there is no injector, skip to lying them down.",
                    "Si no hay inyector, pasa a acostarlos.",
                    bookPic,
                    tick: 5
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
                    picture(chapter, prefer: "cpr-check.png"),
                    tick: 10
                ),
                step(
                    "Hard, fast compressions in the center of the chest. One hundred to one hundred twenty a minute. Let the chest come back up each time. Two inches deep on an adult.",
                    "Compresiones fuertes y rápidas al centro del pecho. Cien a ciento veinte por minuto. Deja que el pecho suba cada vez. Cinco centímetros en un adulto.",
                    "Say the count. Heel of the hand. Do not stand on the chest. Do not bounce.",
                    "Di la cuenta. Talón de la mano. No te subas al pecho. No rebotes.",
                    "Blood has to reach the brain. Shallow pumps do nothing.",
                    "La sangre tiene que llegar al cerebro. Las palmaditas no sirven.",
                    "Stop if an AED is attached and says stay clear, or if they start breathing.",
                    "Para si un DEA dice apartarse o si empiezan a respirar.",
                    picture(chapter, prefer: "cpr-compress.png"),
                    bpm: 110
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
        case .infant:
            body = [
                step(
                    "A baby. Face down on your forearm, head lower than the chest. Five hard back blows between the shoulders. Then look in the mouth. Only sweep what you can see. Not the belly.",
                    "Un bebé. Boca abajo en tu antebrazo, cabeza más baja que el pecho. Cinco golpes fuertes entre los hombros. Luego mira la boca. Solo saca lo que ves. No el vientre.",
                    "Say: I have you. Support the head. Hits go to the back, not the neck.",
                    "Di: te tengo. Sostén la cabeza. Los golpes van a la espalda, no al cuello.",
                    "A baby airway is short. Belly thrusts crush it.",
                    "La vía de un bebé es corta. Los empujes al vientre la aplastan.",
                    "If they cry or cough, stop and watch. If the chest is still, go to the next move.",
                    "Si lloran o tosen, para y vigila. Si el pecho sigue quieto, pasa al siguiente.",
                    bookPic
                ),
                step(
                    "Turn them face up on your other arm. Two fingers in the center of the chest. Five thrusts, one third of the way down. Repeat back blows and chest thrusts.",
                    "Gíralos boca arriba en el otro brazo. Dos dedos al centro del pecho. Cinco empujes, un tercio hacia abajo. Repite espalda y pecho.",
                    "Say the count. Two fingers. Not the belly. Not the throat.",
                    "Di la cuenta. Dos dedos. No el vientre. No la garganta.",
                    "Chest thrusts move a block a belly thrust would lodge.",
                    "El pecho mueve un bloqueo que el vientre clavaría.",
                    "If they go limp, start infant compressions. Look in the mouth each time the chest comes up.",
                    "Si quedan flojos, empieza compresiones de bebé. Mira la boca cada vez que el pecho sube.",
                    bookPic
                ),
                step(
                    "If the chest has stopped: two fingers, center of the chest, one third deep, one hundred to one hundred twenty a minute. Cover the mouth and nose with your mouth only if you know how. Otherwise hands only.",
                    "Si el pecho paró: dos dedos, centro, un tercio, cien a ciento veinte por minuto. Cubre boca y nariz con tu boca solo si sabes. Si no, solo manos.",
                    "Say the count. Keep the head in line. Do not shake the baby.",
                    "Di la cuenta. Cabeza en línea. No sacudas al bebé.",
                    "A baby's heart is under a small sternum. Two fingers. Not a palm.",
                    "El corazón de un bebé está bajo un esternón chico. Dos dedos. No la palma.",
                    "Stop if they cry or breathe, or trained help takes over.",
                    "Para si lloran o respiran, o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png"),
                    bpm: 110
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if they cry it out. A baby can swell later.",
                es: "Consigue ayuda entrenada aunque lloren el bloqueo. Un bebé puede hincharse después."
            )
        case .selfChoke:
            body = [
                step(
                    "If you can cough or make a sound, keep coughing. Do not put fingers in your mouth.",
                    "Si puedes toser o hacer un sonido, sigue tosiendo. No metas los dedos en la boca.",
                    "Say nothing. Cough. Wave someone over if you can.",
                    "No hables. Tose. Llama a alguien con la mano si puedes.",
                    "Air can still move if you cough.",
                    "El aire aún pasa si toses.",
                    "If no air comes out, go to the chair now.",
                    "Si no sale aire, pasa a la silla ya.",
                    bookPic
                ),
                step(
                    "Make a fist above your navel. Bend over a chair back, a counter, or a rail. Drive the fist in and up. Repeat until air moves.",
                    "Haz un puño sobre tu ombligo. Inclínate sobre un respaldo, un mesón o un riel. Empuja el puño adentro y arriba. Repite hasta que pase el aire.",
                    "Fist in. Lean. Drive. Count out loud if you can.",
                    "Puño adentro. Inclínate. Empuja. Cuenta si puedes.",
                    "The chair is the other pair of hands you do not have.",
                    "La silla es el otro par de manos que no tienes.",
                    "If you start to fade, get to the floor before you fall.",
                    "Si te apagas, llega al piso antes de caerte.",
                    bookPic
                ),
                step(
                    "If you go down and someone is there, they start CPR. If you are alone and air is moving, sit and watch your own chest. Do not eat or drink.",
                    "Si te caes y hay alguien, ellos empiezan RCP. Si estás solo y el aire pasa, siéntate y mira tu pecho. No comas ni bebas.",
                    "Hands on your knees. Watch the next breath.",
                    "Manos en las rodillas. Mira la siguiente respiración.",
                    "A second swell can close what you just opened.",
                    "Una segunda hinchazón puede cerrar lo que acabas de abrir.",
                    "If the chest stops and no one is there, you cannot coach yourself. Stay visible.",
                    "Si el pecho para y no hay nadie, no te puedes entrenar solo. Quédate visible.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if the block comes out. You can swell later.",
                es: "Consigue ayuda entrenada aunque salga el bloqueo. Puedes hincharte después."
            )
        case .pregnant:
            body = [
                step(
                    "If they can cough or speak, let them cough. Nothing in the mouth.",
                    "Si pueden toser o hablar, déjalos toser. Nada en la boca.",
                    "Say: cough it out. I will not hit the belly.",
                    "Di: tóselo. No voy a golpear el vientre.",
                    "Air can still move if they cough.",
                    "El aire aún pasa si tosen.",
                    "If they go silent, go to back blows, then chest thrusts.",
                    "Si se callan, pasa a golpes en la espalda, luego empujes al pecho.",
                    bookPic
                ),
                step(
                    "Five hard back blows between the shoulders. Then five chest thrusts on the lower half of the breastbone, not the belly.",
                    "Cinco golpes fuertes entre los hombros. Luego cinco empujes al pecho en la mitad baja del esternón, no el vientre.",
                    "Say: I am going to the chest, not the belly. Count out loud.",
                    "Di: voy al pecho, no al vientre. Cuenta en voz alta.",
                    "A belly thrust on a pregnant belly hits the wrong thing.",
                    "Un empuje al vientre en un embarazo pega donde no es.",
                    "If they go down, start CPR a little higher on the chest. Roll them onto the left side if they breathe again.",
                    "Si se caen, RCP un poco más arriba en el pecho. Gíralos al lado izquierdo si vuelven a respirar.",
                    bookPic
                ),
                step(
                    "If they go down: hard fast compressions, center of the chest, a little higher than usual. Let the chest come back up.",
                    "Si se caen: compresiones fuertes y rápidas, centro del pecho, un poco más arriba. Deja que el pecho suba.",
                    "Say the count. One person pushes. Keep the belly off the ground if you can pad it.",
                    "Di la cuenta. Una persona empuja. El vientre fuera del piso si puedes acolcharlo.",
                    "Blood still has to reach two bodies.",
                    "La sangre tiene que llegar a dos cuerpos.",
                    "Stop if they breathe or trained help takes over.",
                    "Para si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png"),
                    bpm: 110
                ),
            ]
            care = FieldLoc(
                en: "Get trained help even if the block comes out. Two patients.",
                es: "Consigue ayuda entrenada aunque salga el bloqueo. Dos pacientes."
            )
        case .hole:
            body = [
                step(
                    "Sit them if they want to sit. Find the hole. Cover it with a palm, then plastic, tape, or a wrapper. Leave one side open so air can get out.",
                    "Siéntalos si quieren sentarse. Encuentra el hueco. Cúbrelo con la palma, luego plástico, cinta o un envoltorio. Deja un lado abierto para que salga el aire.",
                    "Say: I am covering the hole. Breathe. Palm first. Then the seal.",
                    "Di: cubro el hueco. Respira. Primero la palma. Luego el sello.",
                    "A sealed four-side patch can trap air and drop the lung. Three sides lets the bad air out.",
                    "Un parche de cuatro lados atrapa aire y tira el pulmón. Tres lados dejan salir el aire malo.",
                    "If they get worse after you seal it, lift a corner, then put it back.",
                    "Si empeoran después del sello, levanta una esquina, luego ponlo otra vez.",
                    bookPic
                ),
                step(
                    "Keep the seal. Do not make them walk. Watch the chest. No food. No drink.",
                    "Sigue el sello. No los hagas caminar. Mira el pecho. Sin comida. Sin bebida.",
                    "Say: stay still. I have the hole. Sit next to them.",
                    "Di: quieto. Tengo el hueco. Siéntate a su lado.",
                    "Walking a sucking chest is how they collapse.",
                    "Hacer caminar un pecho que chupa es cómo se caen.",
                    "If the chest stops, start CPR. Keep the seal if you can.",
                    "Si el pecho para, empieza RCP. Sigue el sello si puedes.",
                    bookPic
                ),
                step(
                    "If they fade: lay them on the injured side if they can breathe that way. If the chest stops, hard fast compressions.",
                    "Si se apagan: acuéstalos del lado herido si pueden respirar así. Si el pecho para, compresiones fuertes y rápidas.",
                    "One hand on the seal. One person pushes if it stops.",
                    "Una mano en el sello. Una persona empuja si para.",
                    "The injured side down keeps blood in the good lung.",
                    "El lado herido abajo deja la sangre en el pulmón bueno.",
                    "Stop compressions if they breathe or trained help takes over.",
                    "Para las compresiones si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png"),
                    bpm: 110
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help now. Keep the three-side seal on the way.",
                es: "Llega a ayuda entrenada ya. Sigue el sello de tres lados en el camino."
            )
        case .sugar:
            body = [
                step(
                    "If they can sit and swallow, give them sugar they already have: juice, gel, or four teaspoons of sugar. Do not force it.",
                    "Si pueden sentarse y tragar, dales azúcar que ya tengan: jugo, gel o cuatro cucharaditas. No lo fuerces.",
                    "Say: sip this. Hold the cup. Do not pour it down.",
                    "Di: sorbe esto. Sostén el vaso. No lo viertas.",
                    "A swallow they cannot control is how sugar becomes a choke.",
                    "Un trago que no controlan es cómo el azúcar se ahoga.",
                    "If they cannot swallow or will not wake, nothing in the mouth. Tap STAY.",
                    "Si no tragan o no despiertan, nada en la boca. Toca STAY.",
                    bookPic
                ),
                step(
                    "Wait fifteen minutes. If they talk sense, another sip. No more insulin. No long walk.",
                    "Espera quince minutos. Si hablan con sentido, otro sorbo. Sin más insulina. Sin caminata larga.",
                    "Say: stay sitting. I am watching you. Count with them.",
                    "Di: sigue sentado. Te estoy mirando. Cuenta con ellos.",
                    "A second crash comes when they walk it off.",
                    "Un segundo bajón viene cuando lo caminan.",
                    "If they seize, tap SEIZURE. If the chest stops, tap CPR.",
                    "Si convulsiónan, toca SEIZURE. Si el pecho para, toca CPR.",
                    bookPic,
                    tick: 15
                ),
                step(
                    "If they will not wake: roll them onto their side. Nothing in the mouth. Watch the chest.",
                    "Si no despiertan: gíralos de lado. Nada en la boca. Mira el pecho.",
                    "Hands on the shoulder and the hip. Roll as one piece.",
                    "Manos en el hombro y la cadera. Gira de una pieza.",
                    "Gel in an unconscious mouth is a choke.",
                    "Gel en una boca inconsciente es un ahogo.",
                    "If the chest stops, tap CPR.",
                    "Si el pecho para, toca CPR.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help if they will not wake or cannot keep sugar down.",
                es: "Llega a ayuda entrenada si no despiertan o no retienen el azúcar."
            )
        case .overdose:
            body = [
                step(
                    "If they have their own naloxone, use it now. Nose spray or thigh, however that kit is built. Do not wait to see if they 'sleep it off'.",
                    "Si tienen su naloxona, úsala ya. Nariz o muslo, como sea ese kit. No esperes a ver si 'se les pasa el sueño'.",
                    "Say: I am giving your kit. Then roll them. Hands off the mouth.",
                    "Di: te doy tu kit. Luego gíralos. Manos fuera de la boca.",
                    "The kit is the first move. Waiting is how a chest stops.",
                    "El kit es el primer movimiento. Esperar es cómo para el pecho.",
                    "If there is no kit, skip to the side and watch the chest.",
                    "Si no hay kit, pasa al lado y mira el pecho.",
                    bookPic
                ),
                step(
                    "Roll them onto their side. Tilt the head so the tongue is off the throat. Watch the chest for ten seconds.",
                    "Gíralos de lado. Inclina la cabeza para que la lengua no tape la garganta. Mira el pecho diez segundos.",
                    "Say: I am rolling you. Hands on the shoulder and the hip.",
                    "Di: te giro. Manos en el hombro y la cadera.",
                    "The side keeps vomit out of the airway.",
                    "De lado el vómito no tapa el aire.",
                    "If there is no normal breathing, start compressions.",
                    "Si no hay respiración normal, empieza compresiones.",
                    bookPic,
                    tick: 10
                ),
                step(
                    "If the chest has stopped: hard fast compressions in the center of the chest. A second naloxone after three minutes if they have it and they are still out.",
                    "Si el pecho paró: compresiones fuertes y rápidas al centro. Una segunda naloxona a los tres minutos si tienen y siguen fuera.",
                    "Say the count. One person pushes. Keep the kit with them.",
                    "Di la cuenta. Una persona empuja. El kit va con ellos.",
                    "A closed chest becomes no pulse. The kit still has to go with them.",
                    "Un pecho cerrado se vuelve sin pulso. El kit tiene que ir con ellos.",
                    "Stop if they breathe or trained help takes over.",
                    "Para si respiran o la ayuda entrenada toma el relevo.",
                    picture(chapter, prefer: "cpr-compress.png"),
                    bpm: 110
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help with the kit. They can stop again after they wake.",
                es: "Llega a ayuda entrenada con el kit. Pueden parar otra vez después de despertar."
            )
        case .tight:
            body = [
                step(
                    "A limb that still pours after pressure: windlass two to three inches above the wound, not on a joint. Twist until the bleed slows. Write the time on the skin.",
                    "Una extremidad que chorrea después de la presión: torniquete cinco a siete centímetros arriba, no en una articulación. Gira hasta que afloje. Escribe la hora en la piel.",
                    "Say: this will hurt. Hurting means it is working. Twist. Note the time out loud.",
                    "Di: esto va a doler. El dolor significa que funciona. Gira. Di la hora en voz alta.",
                    "A loose strap is jewelry. Tight enough that a finger cannot slip under.",
                    "Una correa floja es adorno. Tan apretada que no quepa un dedo.",
                    "Never on the neck. Never loosen it to check.",
                    "Nunca en el cuello. Nunca lo aflojes para mirar.",
                    picture(chapter, prefer: "bleed-tq.png")
                ),
                step(
                    "If you have no windlass, a belt plus a stick. Same height. Twist. Hold the twist.",
                    "Si no hay torniquete, un cinturón y un palo. Misma altura. Gira. Sostén el giro.",
                    "Say: hold this twist. Do not let it unwind.",
                    "Di: sostén este giro. Que no se suelte.",
                    "An improvised strap that is not twisted does nothing.",
                    "Una correa improvisada sin giro no hace nada.",
                    "If the bleed is in the groin or armpit, you cannot tourniquet it. Pack and press. Tap BLEED.",
                    "Si el sangrado es en la ingle o la axila, no hay torniquete. Tapa y presiona. Toca BLEED.",
                    picture(chapter, prefer: "bleed-tq.png")
                ),
                step(
                    "Keep the twist. Keep them warm. No food. Watch the chest.",
                    "Sigue el giro. Mantenlos calientes. Sin comida. Mira el pecho.",
                    "Say: I will not loosen it. Sit by the limb.",
                    "Di: no lo voy a aflojar. Siéntate junto al miembro.",
                    "Loosening to 'let blood in' is how they bleed out on the walk.",
                    "Aflojar para 'dejar entrar sangre' es cómo se desangran en el camino.",
                    "If they fade, tap SHOCK. If the chest stops, tap CPR.",
                    "Si se apagan, toca SHOCK. Si el pecho para, toca CPR.",
                    bleedPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help with the time you wrote. Do not loosen it on the way.",
                es: "Llega a ayuda entrenada con la hora que escribiste. No lo aflojes en el camino."
            )
        case .stuck:
            body = [
                step(
                    "Leave the object where it is. Pack cloth around it so it cannot wobble. Do not pull it out.",
                    "Deja el objeto donde está. Tapa con tela alrededor para que no se mueva. No lo saques.",
                    "Say: do not pull it. Hold the cloth, not the object.",
                    "Di: no lo saques. Sostén la tela, no el objeto.",
                    "The object is the plug. Pulling it opens the vessel.",
                    "El objeto es el tapón. Sacarlo abre el vaso.",
                    "If it is in the chest and the chest sucks, tap HOLE and seal around it.",
                    "Si está en el pecho y el pecho chupa, toca HOLE y sella alrededor.",
                    bleedPic
                ),
                step(
                    "Press around the object, not on it. Keep them still. No food. No drink.",
                    "Presiona alrededor del objeto, no encima. Mantenlos quietos. Sin comida. Sin bebida.",
                    "Say: stay still. I have the wound. Both hands on the cloth.",
                    "Di: quieto. Tengo la herida. Las dos manos en la tela.",
                    "Walking with a wobbling object tears more.",
                    "Caminar con un objeto que se mueve rasga más.",
                    "If they fade, tap SHOCK. If the chest stops, tap CPR.",
                    "Si se apagan, toca SHOCK. Si el pecho para, toca CPR.",
                    bleedPic
                ),
                step(
                    "Carry them if you can. The object stays. Watch the chest.",
                    "Cárgalos si puedes. El objeto se queda. Mira el pecho.",
                    "One person holds the pack. One person moves the body.",
                    "Uno sostiene el tapón. Otro mueve el cuerpo.",
                    "A pulled object on the trail is a bleed you cannot put back.",
                    "Un objeto sacado en el camino es un sangrado que no puedes devolver.",
                    "Stop if trained help takes the wound.",
                    "Para si la ayuda entrenada toma la herida.",
                    bleedPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help with the object still in. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada con el objeto aún dentro. No esperes un número que el visor no puede marcar."
            )
        case .breath:
            body = [
                step(
                    "Sit them up if they can sit. If you are the one who cannot breathe, sit, hands on your knees. Look at the chest.",
                    "Siéntalos si pueden sentarse. Si eres tú quien no puede respirar, siéntate, manos en las rodillas. Mira el pecho.",
                    "Hands on their shoulders — or on your own knees. Watch the mouth.",
                    "Manos en sus hombros — o en tus rodillas. Mira la boca.",
                    "Sitting opens the chest. Lying flat steals the air they have left.",
                    "Sentados abre el pecho. Acostados les roba el aire que les queda.",
                    "If they collapse or the chest stops, tap CPR.",
                    "Si se caen o el pecho para, toca CPR.",
                    bookPic
                ),
                step(
                    "Ask: can you cough? Can you say a word? If they cannot, tap CHOKE. Do not put fingers in the mouth.",
                    "Pregunta: ¿puedes toser? ¿Puedes decir una palabra? Si no pueden, toca CHOKE. No metas los dedos en la boca.",
                    "Listen. Watch the mouth. Hands off the throat.",
                    "Escucha. Mira la boca. Manos fuera de la garganta.",
                    "A person who can cough still has an open throat. A silent chest is the block.",
                    "Quien puede toser aún tiene la garganta abierta. Un pecho silencioso es el bloqueo.",
                    "If the face or tongue is swelling, tap ALLERGY now.",
                    "Si la cara o la lengua hinchan, toca ALLERGY ya.",
                    bookPic
                ),
                step(
                    "Loosen the collar. Do not make them walk. Do not lay them flat if they are fighting for air. Wheeze and an inhaler: tap ASTHMA. Chest pain: tap HEART. Chest stopped: tap CPR.",
                    "Afloja el cuello. No los hagas caminar. No los acuestes si pelean por aire. Silbido e inhalador: toca ASTHMA. Dolor de pecho: toca HEART. Pecho parado: toca CPR.",
                    "Hands on the collar, not on a bottle. Stay next to them.",
                    "Manos en el cuello, no en una botella. Quédate a su lado.",
                    "Walking and lying flat both steal the air. The cause chips are the next move.",
                    "Caminar y acostarse roban el aire. Las fichas de causa son el siguiente movimiento.",
                    "If none of those is it and they still breathe, tap STAY.",
                    "Si ninguna es y aún respiran, toca STAY.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help. Stay sitting. Do not wait on a number the glass cannot dial.",
                es: "Llega a ayuda entrenada. Sigue sentado. No esperes un número que el visor no puede marcar."
            )
        case .hurt:
            body = [
                step(
                    "Look for blood you can see and whether the chest is moving. If fire, traffic, or falling rock will hit them, move them. Else stay.",
                    "Busca sangre que se vea y si el pecho se mueve. Si el fuego, el tráfico o una roca los va a pegar, muévelos. Si no, quédate.",
                    "Eyes on the body. Then one hand. Then the cause chips.",
                    "Ojos en el cuerpo. Luego una mano. Luego las fichas de causa.",
                    "Bleed and breath kill first. The rest can wait one look.",
                    "Sangrado y aire matan primero. El resto puede esperar una mirada.",
                    "If the scene is still hitting them, move, then look again.",
                    "Si la escena aún los pega, muévete, luego mira otra vez.",
                    bookPic
                ),
                step(
                    "Blood you can see: tap BLEED and press now. Silent chest or no air: tap BREATH or CPR.",
                    "Sangre que se ve: toca BLEED y presiona ya. Pecho silencioso o sin aire: toca BREATH o CPR.",
                    "Hands on the cloth or on the shoulders. Not both at once.",
                    "Manos en el paño o en los hombros. No las dos a la vez.",
                    "A bleed that waits on a guess restarts. A silent chest becomes no pulse.",
                    "Un sangrado que espera una duda vuelve. Un pecho silencioso se vuelve sin pulso.",
                    "If they are talking and the blood is a trickle, keep looking.",
                    "Si hablan y la sangre es un hilo, sigue mirando.",
                    bleedPic
                ),
                step(
                    "Head hit or knocked out: tap HEAD. Fell or the neck hurts: tap NECK. A bone that will not hold: tap BREAK. Burned skin: tap BURN. A bite or sting: tap BITE. None of those: tap STAY.",
                    "Golpe en la cabeza o desmayo: toca HEAD. Cayó o duele el cuello: toca NECK. Un hueso que no sostiene: toca BREAK. Piel quemada: toca BURN. Mordida o picadura: toca BITE. Nada de eso: toca STAY.",
                    "Name the next chip out loud. Then tap it.",
                    "Di la ficha en voz alta. Luego tócala.",
                    "The chips are the rest of the walk. Guessing past a bleed wastes the minute.",
                    "Las fichas son el resto del camino. Adivinar pasado un sangrado gasta el minuto.",
                    "If they fade, go back to BLEED or CPR.",
                    "Si se apagan, vuelve a BLEED o CPR.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help. Keep pressure and the airway on the way.",
                es: "Llega a ayuda entrenada. Sigue la presión y la vía aérea en el camino."
            )
        case .sick:
            body = [
                step(
                    "Sit them in shade. Loosen cloth. Ask: what hurts, and can they talk sense?",
                    "Siéntalos a la sombra. Afloja la ropa. Pregunta: qué duele, y ¿hablan con sentido?",
                    "Hands on the shoulders. Listen. Watch the face.",
                    "Manos en los hombros. Escucha. Mira la cara.",
                    "Sense and sweat tell heat from a stroke from a gut.",
                    "El sentido y el sudor dicen calor, derrame o estómago.",
                    "If they collapse, tap CPR.",
                    "Si se caen, toca CPR.",
                    bookPic
                ),
                step(
                    "Hot and confused: tap HEAT. Wet and shaking: tap COLD. Face, arm, or speech gone: tap STROKE. Swell or sting: tap ALLERGY. Shaking they cannot stop: tap SEIZURE.",
                    "Calor y confusión: toca HEAT. Mojado y temblando: toca COLD. Cara, brazo o habla rara: toca STROKE. Hincha o picadura: toca ALLERGY. Temblor que no para: toca SEIZURE.",
                    "Name the chip. Then tap it. Stay next to them.",
                    "Di la ficha. Luego tócala. Quédate a su lado.",
                    "The first matching cause is the walk. Stacking causes skips the one that is killing them.",
                    "La primera causa que cabe es el camino. Apilar causas se salta la que los mata.",
                    "If they start to vomit, roll them and keep going.",
                    "Si vomitan, gíralos y sigue.",
                    bookPic
                ),
                step(
                    "Throwing up: roll them onto their side. No food. Watch the chest. Gut pain or diarrhea: tap GUT. A bottle or plant they swallowed: tap POISON. None of those: tap STAY.",
                    "Si vomitan: gíralos de lado. Sin comida. Mira el pecho. Dolor de panza o diarrea: toca GUT. Una botella o planta que tragaron: toca POISON. Nada de eso: toca STAY.",
                    "Hands on the shoulder. Roll. Then sit.",
                    "Manos en el hombro. Gira. Luego siéntate.",
                    "A swallow they cannot control is how sick becomes a choke.",
                    "Un trago que no controlan es cómo un enfermo se ahoga.",
                    "If the chest stops, tap CPR.",
                    "Si el pecho para, toca CPR.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Get to trained help if they will not wake, will not make sense, or cannot keep water down.",
                es: "Llega a ayuda entrenada si no despiertan, no tienen sentido o no retienen agua."
            )
        case .stay:
            body = [
                step(
                    "They are breathing. If they will not stay awake, roll them onto their side. Tilt the head so the tongue is off the throat.",
                    "Están respirando. Si no se mantienen despiertos, gíralos de lado. Inclina la cabeza para que la lengua no tape la garganta.",
                    "Hands on the shoulder and the hip. Roll as one piece.",
                    "Manos en el hombro y la cadera. Gira de una pieza.",
                    "The side keeps spit and the tongue out of the airway.",
                    "De lado la saliva y la lengua no tapan el aire.",
                    "If the chest stops, tap CPR.",
                    "Si el pecho para, toca CPR.",
                    bookPic
                ),
                step(
                    "Jacket on the trunk. Shade or a windbreak. No food, no drink, no alcohol.",
                    "Chaqueta en el tronco. Sombra o un rompeviento. Sin comida, sin bebida, sin alcohol.",
                    "Cover the trunk. Hands off the bottle.",
                    "Cubre el tronco. Manos fuera de la botella.",
                    "A drink they cannot swallow is how a stable person chokes. Alcohol dumps the last heat.",
                    "Una bebida que no pueden tragar es cómo un estable se ahoga. El alcohol tira el último calor.",
                    "If they start to shake from cold, add a layer. If they overheat, shade and fan.",
                    "Si tiemblan de frío, otra capa. Si se calientan, sombra y abanico.",
                    bookPic
                ),
                step(
                    "Watch the chest. If it stops, tap CPR. Stay visible. Yell in threes. Do not leave them.",
                    "Mira el pecho. Si para, toca CPR. Quédate visible. Grita de a tres. No los dejes.",
                    "Sit by the head. Count breaths out loud.",
                    "Siéntate junto a la cabeza. Cuenta las respiraciones.",
                    "A person left alone is the one who dies on the walk for help.",
                    "Quien se queda solo es el que muere en el camino a pedir ayuda.",
                    "Stop if trained help takes over.",
                    "Para si la ayuda entrenada toma el relevo.",
                    bookPic
                ),
            ]
            care = FieldLoc(
                en: "Stay with them until a known voice reaches you. Do not wait on a number the glass cannot dial.",
                es: "Quédate hasta que una voz conocida te alcance. No esperes un número que el visor no puede marcar."
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
        _ image: String,
        tick: Int? = nil,
        bpm: Int? = nil
    ) -> FieldStep {
        FieldStep(
            do: FieldLoc(en: doEn, es: doEs),
            why: FieldLoc(en: whyEn, es: whyEs),
            child: FieldLoc(en: childEn, es: childEs),
            stop: FieldLoc(en: stopEn, es: stopEs),
            image: image,
            tickSeconds: tick,
            metronomeBpm: bpm
        )
    }
}
