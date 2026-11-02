/// Traducciones breves de citas documentadas en docs/DRUMMER_QUOTES.md.
struct DrummerQuote {
    let text: String
    let author: String

    static let all: [DrummerQuote] = [
        .init(text: "La música siempre será joven.", author: "Buddy Rich"),
        .init(text: "El genio es el fuego que se enciende solo.", author: "Neil Peart"),
        .init(text: "El secreto de la vida: levantarte por la mañana e ir a trabajar.", author: "Neil Peart"),
        .init(text: "¿Qué es lo más excelente que puedo hacer hoy?", author: "Neil Peart"),
        .init(text: "La batería es mi segundo nombre.", author: "Ringo Starr"),
        .init(text: "Tocaba la batería porque la amaba.", author: "Ringo Starr"),
        .init(text: "Mi alma es la de un batería.", author: "Ringo Starr"),
        .init(text: "El aburrimiento, el silencio y el aislamiento forman parte de la creatividad.", author: "Questlove"),
        .init(text: "A veces siento que soy mejor alumno que profesor o creador.", author: "Questlove"),
        .init(text: "Todavía no sé si soy verdaderamente creativo.", author: "Questlove"),
        .init(text: "No hay bien ni mal. Solo existe tu propia voz.", author: "Dave Grohl"),
        .init(text: "Lo que más importa es que sea tu voz. Cuídala, respétala, cultívala.", author: "Dave Grohl"),
        .init(text: "Soy un currante, tío.", author: "Dave Grohl"),
        .init(text: "Músico sería suficiente.", author: "Dave Grohl"),
        .init(text: "La vida es mucho más grande que cualquier banda.", author: "Dave Grohl"),
        .init(text: "El espacio es la parte más importante de la música.", author: "Sheila E."),
        .init(text: "El espacio permite que la canción respire.", author: "Sheila E."),
        .init(text: "No hay límites, leyes ni reglas: hagamos lo que queramos.", author: "Sheila E."),
        .init(text: "La primera mujer batería que vi en televisión fue Karen Carpenter.", author: "Sheila E."),
        .init(text: "¡Espera! La anticipación es la mitad de la diversión.", author: "Phil Collins"),
        .init(text: "El mundo está en tus manos: ahora úsalas.", author: "Phil Collins"),
        .init(text: "A partir de cierto punto, la música ya no es mía: es tuya.", author: "Phil Collins"),
        .init(text: "Ante todo, soy batería.", author: "Ringo Starr"),
        .init(text: "Llegó un momento en que decidí: iba a ser batería.", author: "Ringo Starr"),
        .init(text: "Lo demás ya no importa. Toco la batería.", author: "Ringo Starr"),
        .init(text: "Soy un gran fan de los Beatles. Aunque, sin que nadie lo supiera, antes fui uno.", author: "Ringo Starr"),
        .init(text: "Las aventuras son horribles cuando las estás viviendo.", author: "Neil Peart"),
        .init(text: "Todo con moderación, salvo algún exceso de vez en cuando.", author: "Neil Peart"),
        .init(text: "Unos pocos tipos con armas pueden estropearlo todo.", author: "Neil Peart"),
        .init(text: "El hip-hop es una carrera de gratificación instantánea, ganadores y perdedores.", author: "Questlove")
    ]

    static func random() -> DrummerQuote { all.randomElement()! }
}
