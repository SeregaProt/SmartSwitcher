#!/usr/bin/env python3
"""Генератор ресурсов детектора из частотных списков (hermitdave/FrequencyWords, CC-BY-SA).

Вход:  <lang>_50k.txt — строки "слово частота".
Выход: Resources/<lang>_words.txt  — топ-N слов (по одному в строке)
       Resources/<lang>_ngrams.tsv — условная символьная модель:
           "bc\tP(c|b)"    — биграммная часть (2 символа),
           "abc\tP(c|ab)"  — триграммная часть (3 символа);
         границы слова: "^^" в начале, "$" в конце. Интерполяцию и штраф
         за невиданные n-граммы считает Swift-код (NGramModel).
       Fixtures/eval_<lang>_oov.txt — отложенная выборка (ранги после
         TRAIN_N): не входит ни в словарь, ни в обучение модели — по ней
         честно меряются recall и ложные срабатывания вне словаря.
"""
import re
import sys
from collections import defaultdict

LATIN = re.compile(r"^[a-z']+$")
CYRILLIC = re.compile(r"^[а-яё]+$")
TOP_N = 9000
TRAIN_N = 40000
OOV_N = 3000


def main(src, lang, words_out, ngrams_out, oov_out):
    pattern = CYRILLIC if lang == "ru" else LATIN
    entries = []
    with open(src, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            word, freq = parts[0].lower(), float(parts[1])
            if pattern.match(word):
                entries.append((word, freq))

    with open(words_out, "w", encoding="utf-8") as f:
        f.write("\n".join(w for w, _ in entries[:TOP_N]) + "\n")

    bigrams, trigrams = defaultdict(float), defaultdict(float)
    uni_ctx, bi_ctx = defaultdict(float), defaultdict(float)
    for word, freq in entries[:TRAIN_N]:
        letters = word.replace("'", "")
        if not letters:
            continue
        marked = "^^" + letters + "$"
        for i in range(1, len(marked) - 1):
            bigrams[marked[i:i + 2]] += freq
            uni_ctx[marked[i]] += freq
        for i in range(len(marked) - 2):
            trigrams[marked[i:i + 3]] += freq
            bi_ctx[marked[i:i + 2]] += freq

    with open(ngrams_out, "w", encoding="utf-8") as f:
        for bg, count in sorted(bigrams.items(), key=lambda x: -x[1]):
            f.write(f"{bg}\t{count / uni_ctx[bg[0]]:.6g}\n")
        for tg, count in sorted(trigrams.items(), key=lambda x: -x[1]):
            f.write(f"{tg}\t{count / bi_ctx[tg[:2]]:.6g}\n")

    oov = [w for w, _ in entries[TRAIN_N:] if len(w.replace("'", "")) >= 2][:OOV_N]
    with open(oov_out, "w", encoding="utf-8") as f:
        f.write("\n".join(oov) + "\n")

    print(f"{lang}: {min(len(entries), TOP_N)} слов, {len(bigrams)} биграмм, "
          f"{len(trigrams)} триграмм, {len(oov)} OOV для оценки")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit("usage: generate_language_data.py <src_50k.txt> <ru|en> <words_out> <ngrams_out> <oov_out>")
    main(*sys.argv[1:])
