/// Встроенный мини-словарь: фолбэк DictionaryService на случай, если
/// ресурсы бандла не загрузились (graceful degradation).
public enum LanguageData {
    // MARK: - Английский


    public static let englishWords: Set<String> = [
        // служебные и сверхчастотные
        "a", "i", "the", "be", "to", "of", "and", "in", "that", "have",
        "it", "for", "not", "on", "with", "he", "as", "you", "do", "at",
        "this", "but", "his", "by", "from", "they", "we", "say", "her", "she",
        "or", "an", "will", "my", "one", "all", "would", "there", "their", "what",
        "so", "up", "out", "if", "about", "who", "get", "which", "go", "me",
        "when", "make", "can", "like", "time", "no", "just", "him", "know", "take",
        "people", "into", "year", "your", "good", "some", "could", "them", "see", "other",
        "than", "then", "now", "look", "only", "come", "its", "over", "think", "also",
        "back", "after", "use", "two", "how", "our", "work", "first", "well", "way",
        "even", "new", "want", "because", "any", "these", "give", "day", "most", "us",
        "is", "was", "are", "were", "been", "has", "had", "did", "said", "each",
        "where", "why", "must", "very", "through", "before", "here", "too", "much", "both",
        "those", "while", "should", "never", "every", "again", "between", "under", "last", "right",
        "left", "off", "down", "still", "own", "might", "next", "once", "always", "often",
        "thing", "things", "something", "nothing", "anything", "everything", "world", "life", "hand", "part",
        "place", "case", "week", "company", "system", "program", "question", "number", "night", "point",
        "home", "water", "room", "mother", "father", "area", "money", "story", "fact", "month",
        "lot", "study", "book", "eye", "job", "word", "words", "business", "issue", "side",
        "kind", "head", "house", "service", "friend", "friends", "power", "hour", "game", "line",
        "end", "member", "law", "car", "city", "name", "team", "minute", "idea", "body",
        "information", "long", "little", "great", "high", "small", "large", "big", "old", "young",
        "different", "important", "few", "public", "bad", "same", "able", "need", "feel", "three",
        "state", "tell", "may", "call", "try", "ask", "find", "show", "play", "move",
        "live", "believe", "hold", "bring", "happen", "write", "provide", "sit", "stand", "lose",
        "pay", "meet", "include", "continue", "set", "learn", "change", "lead", "understand", "watch",
        "follow", "stop", "create", "speak", "read", "allow", "add", "spend", "grow", "open",
        "walk", "win", "offer", "remember", "love", "consider", "appear", "buy", "wait", "serve",
        "send", "expect", "build", "stay", "fall", "cut", "reach", "kill", "remain", "today",
        "tomorrow", "yesterday", "morning", "evening", "really", "actually", "probably", "maybe", "sure", "yes",
        "yeah", "yep", "no", "nope", "ok", "okay", "fine", "nice", "cool", "best",
        "better", "hello", "hi", "hey", "please", "thanks", "thank", "sorry", "bye", "welcome",
        // разговорные сокращения и интернет-лексика
        "btw", "tbh", "omg", "idk", "lol", "brb", "thx", "pls", "plz", "np",
        "fyi", "imo", "imho", "asap", "aka", "etc", "wtf", "lmao", "gg", "wp",
        "mr", "mrs", "ms", "dr", "vs",
        // сокращения с апострофом и без
        "dont", "cant", "wont", "didnt", "doesnt", "isnt", "wasnt", "arent", "im", "ive",
        "youre", "youve", "hes", "shes", "lets", "thats", "whats", "theres", "wouldnt", "couldnt",
        "don't", "can't", "won't", "didn't", "doesn't", "isn't", "wasn't", "aren't", "i'm", "i've",
        "you're", "you've", "he's", "she's", "let's", "that's", "what's", "there's", "wouldn't", "couldn't",
        "it's", "we're", "they're", "i'll", "you'll", "we'll", "haven't", "hasn't", "shouldn't", "wasn't",
        // техническая лексика
        "code", "file", "files", "data", "user", "users", "mail", "email", "text", "type",
        "click", "link", "page", "site", "web", "app", "apps", "mac", "macos", "swift",
        "test", "tests", "build", "run", "debug", "release", "update", "version", "server", "client",
        "branch", "commit", "merge", "push", "pull", "main", "dev", "bug", "fix", "api",
        "json", "http", "https", "git", "github", "xcode", "terminal", "shell", "script", "log",
    ]


    // MARK: - Русский


    public static let russianWords: Set<String> = [
        // сверхчастотные
        "и", "в", "не", "на", "я", "быть", "он", "с", "что", "а",
        "по", "это", "она", "этот", "к", "но", "они", "мы", "как", "из",
        "у", "который", "то", "за", "свой", "весь", "год", "от", "так", "о",
        "для", "ты", "же", "все", "всё", "тот", "мочь", "вы", "человек", "такой",
        "его", "сказать", "только", "или", "ещё", "еще", "бы", "себя", "один", "уже",
        "до", "время", "если", "сам", "когда", "другой", "вот", "говорить", "наш", "мой",
        "знать", "стать", "при", "чтобы", "дело", "жизнь", "кто", "первый", "очень", "два",
        "день", "её", "новый", "рука", "даже", "во", "со", "раз", "где", "там",
        "под", "можно", "ну", "какой", "после", "их", "работа", "без", "самый", "потом",
        "надо", "хотеть", "ли", "слово", "слова", "идти", "большой", "должен", "место", "иметь",
        "ничего", "сейчас", "тут", "лицо", "каждый", "друг", "нет", "теперь", "жизнь", "может",
        "люди", "земля", "конец", "час", "голова", "видеть", "дом", "дома", "домой", "стоить",
        "ничто", "пойти", "хорошо", "плохо", "почему", "зачем", "тоже", "также", "много", "мало",
        "просто", "сложно", "именно", "вообще", "опять", "снова", "здесь", "туда", "сюда", "оттуда",
        // разговорные и приветствия
        "привет", "пока", "спасибо", "пожалуйста", "да", "нет", "ага", "угу", "ок", "окей",
        "здравствуй", "здравствуйте", "добрый", "доброе", "утро", "утром", "вечер", "вечером", "ночь", "ночью",
        "сегодня", "завтра", "вчера", "давай", "давайте", "конечно", "наверное", "точно", "ладно", "хорошего",
        "мама", "папа", "брат", "сестра", "семья", "дети", "ребенок", "ребёнок", "жена", "муж",
        "дела", "делать", "сделать", "работать", "думать", "понять", "понимать", "смотреть", "слушать", "писать",
        "читать", "купить", "продать", "найти", "искать", "ждать", "помочь", "помощь", "вопрос", "ответ",
        "деньги", "город", "москва", "россия", "страна", "мир", "война", "любовь", "любить", "нравиться",
        "красивый", "интересный", "важный", "нужный", "нужно", "можем", "хочу", "хочешь", "хочет", "буду",
        "будет", "будем", "была", "было", "были", "есть", "поесть", "вода", "еда", "кофе",
        "чай", "магазин", "машина", "телефон", "компьютер", "интернет", "файл", "письмо", "почта", "встреча",
        "минута", "секунда", "неделя", "месяц", "лет", "года", "номер", "телефон", "адрес", "улица",
        "квартира", "офис", "школа", "университет", "книга", "музыка", "фильм", "игра", "новости", "погода",
    ]


    // MARK: - Доступ по языку


    public static func words(for layout: Layout) -> Set<String> {
        layout == .en ? englishWords : russianWords
    }

}
