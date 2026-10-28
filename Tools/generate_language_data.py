#!/usr/bin/env python3
"""Генератор ресурсов детектора из частотных списков (hermitdave/FrequencyWords, CC-BY-SA).

Вход:  <lang>_50k.txt — строки "слово частота".
Выход: Resources/<lang>_words.txt   — топ-N слов (по одному в строке)
       Resources/<lang>_bigrams.tsv — биграмма \t log10-вероятность
"""
import math
import re
import sys
from collections import defaultdict

LATIN = re.compile(r"^[a-z']+$")
CYRILLIC = re.compile(r"^[а-яё]+$")

def main(src, lang, words_out, bigrams_out, top_n=9000):
    pattern = CYRILLIC if lang == "ru" else LATIN
    words = []
    bigram_counts = defaultdict(float)
    total = 0.0
    with open(src, encoding="utf-8") as f:
        for line in f:
            parts = line.split()
            if len(parts) != 2:
                continue
            word, freq = parts[0].lower(), float(parts[1])
            if not pattern.match(word):
                continue
            words.append(word)
            # биграммы с границами слова (^ и $), взвешенные частотой
            marked = "^" + word + "$"
            for i in range(len(marked) - 1):
                bigram_counts[marked[i:i+2]] += freq
                total += freq

    with open(words_out, "w", encoding="utf-8") as f:
        f.write("\n".join(words[:top_n]) + "\n")

    # log10 вероятности; floor для невиданных биграмм задаётся в коде Swift
    with open(bigrams_out, "w", encoding="utf-8") as f:
        for bg, count in sorted(bigram_counts.items(), key=lambda x: -x[1]):
            logp = math.log10(count / total)
            f.write(f"{bg}\t{logp:.4f}\n")

    print(f"{lang}: {min(len(words), top_n)} слов, {len(bigram_counts)} биграмм")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4])
