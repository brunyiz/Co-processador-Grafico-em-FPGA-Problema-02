#!/usr/bin/env python3
"""Montador minimo da ISA grafica (.gasm) -> palavras de 32 bits.

Uso:  python3 montador_gasm.py programa_grafico.gasm [--c]
Saida padrao: uma palavra hexadecimal por linha, com a linha de origem.
Com --c: vetor C pronto para colar em um programa.

Sintaxe (ver docs/ISA_instruction.txt para os campos):
  TILE x y cor_hex
  SPRITE id x y visivel espelho transp     espelho: 0 normal, 1 X, 2 Y, 3 X+Y
  RECT_P1 x y cor_hex      RECT_P2 x y
  TRI_P1 x y cor_hex       TRI_P2 x y       TRI_P3 x y
  BG_SCROLL RIGHT|LEFT|UP|DOWN n           (n = 1..15)
  VSYNC
Comentarios comecam com #.
"""
import sys

DIRECOES = {"RIGHT": 0, "LEFT": 1, "UP": 2, "DOWN": 3}


def faixa(nome, v, lo, hi):
    if not lo <= v <= hi:
        raise ValueError(f"{nome}={v} fora de {lo}..{hi}")
    return v


def vertice(op, etapa, x, y, cor):
    faixa("X", x, 0, 319)
    faixa("Y", y, 0, 239)
    faixa("cor", cor, 0, 255)
    return (op << 28) | (etapa << 26) | (x << 17) | (y << 9) | (cor << 1)


def montar(linha):
    t = linha.split("#")[0].split()
    if not t:
        return None
    m, a = t[0].upper(), t[1:]
    if m == "VSYNC":
        return 0x5 << 28
    if m == "TILE":
        x, y, c = int(a[0]), int(a[1]), int(a[2], 16)
        return (1 << 28) | (faixa("x", x, 0, 39) << 22) | (faixa("y", y, 0, 29) << 17) | faixa("cor", c, 0, 255)
    if m == "SPRITE":
        i, x, y, v, e, tr = (int(s) for s in a[:6])
        return ((2 << 28) | (faixa("id", i, 0, 31) << 23) | (faixa("x", x, 0, 304) << 14)
                | (faixa("y", y, 0, 224) << 6) | (faixa("vis", v, 0, 1) << 5)
                | (faixa("esp", e, 0, 3) << 3) | (faixa("transp", tr, 0, 1) << 2))
    if m in ("RECT_P1", "RECT_P2"):
        p1 = m.endswith("1")
        return vertice(3, 0 if p1 else 1, int(a[0]), int(a[1]), int(a[2], 16) if p1 else 0)
    if m in ("TRI_P1", "TRI_P2", "TRI_P3"):
        e = int(m[-1]) - 1
        return vertice(4, e, int(a[0]), int(a[1]), int(a[2], 16) if e == 0 else 0)
    if m == "BG_SCROLL":
        return (6 << 28) | (DIRECOES[a[0].upper()] << 26) | (faixa("n", int(a[1]), 1, 15) << 22)
    raise ValueError(f"instrucao desconhecida: {m}")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    saida_c = "--c" in sys.argv
    palavras = []
    for n, linha in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
        try:
            w = montar(linha)
        except Exception as e:  # noqa: BLE001
            sys.exit(f"{sys.argv[1]}:{n}: {e}")
        if w is not None:
            palavras.append((w, linha.split("#")[0].strip()))
    if saida_c:
        print("static const unsigned programa[] = {")
        for w, src in palavras:
            print(f"    0x{w:08X}U, /* {src} */")
        print("};")
    else:
        for w, src in palavras:
            print(f"0x{w:08X}  {src}")


if __name__ == "__main__":
    main()
