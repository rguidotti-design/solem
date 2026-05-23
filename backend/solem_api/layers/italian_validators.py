"""ITALIAN VALIDATORS — Codice Fiscale, IBAN, P.IVA, PEC.

Single responsibility: SOLO validazione algoritmica (no lookup remoti).
Funzioni utili per app italiane (fatturazione, contratti, anagrafica).
"""
from __future__ import annotations

import re
import string

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

router = APIRouter(prefix="/it", tags=["italian-validators"])


class ValidationResult(BaseModel):
    valid: bool
    input: str
    normalized: str | None = None
    details: dict = {}


# ─── Codice Fiscale ────────────────────────────────────────────────────


CF_PATTERN = re.compile(r"^[A-Z]{6}[0-9]{2}[A-EHLMPRST][0-9]{2}[A-Z][0-9]{3}[A-Z]$")

CF_CHECK_ODD = {
    "0": 1, "1": 0, "2": 5, "3": 7, "4": 9, "5": 13, "6": 15, "7": 17, "8": 19, "9": 21,
    "A": 1, "B": 0, "C": 5, "D": 7, "E": 9, "F": 13, "G": 15, "H": 17, "I": 19, "J": 21,
    "K": 2, "L": 4, "M": 18, "N": 20, "O": 11, "P": 3, "Q": 6, "R": 8, "S": 12, "T": 14,
    "U": 16, "V": 10, "W": 22, "X": 25, "Y": 24, "Z": 23,
}
CF_CHECK_EVEN = {
    **{c: i for i, c in enumerate(string.digits)},
    **{c: i for i, c in enumerate(string.ascii_uppercase)},
}


def _cf_checksum(cf15: str) -> str:
    s = 0
    for i, c in enumerate(cf15, start=1):
        if i % 2 == 1:  # odd position (1-based)
            s += CF_CHECK_ODD[c]
        else:
            s += CF_CHECK_EVEN[c]
    return string.ascii_uppercase[s % 26]


@router.post("/codice-fiscale", response_model=ValidationResult)
async def validate_codice_fiscale(payload: dict) -> ValidationResult:
    cf = (payload.get("value") or "").upper().replace(" ", "").strip()
    if len(cf) != 16:
        return ValidationResult(valid=False, input=cf, details={"reason": "length", "got": len(cf)})
    if not CF_PATTERN.match(cf):
        return ValidationResult(valid=False, input=cf, details={"reason": "pattern_mismatch"})

    expected_check = _cf_checksum(cf[:15])
    valid = cf[15] == expected_check

    # Estrai info: M/F dal mese (>40 = donna)
    month_char = cf[8]
    day_str = cf[9:11]
    try:
        day = int(day_str)
        sex = "F" if day > 40 else "M"
        birth_day = day - 40 if sex == "F" else day
    except ValueError:
        sex = "?"
        birth_day = 0

    return ValidationResult(
        valid=valid,
        input=cf,
        normalized=cf,
        details={
            "sex": sex,
            "birth_day": birth_day,
            "month_code": month_char,
            "comune_code": cf[11:15],
            "checksum_expected": expected_check,
            "checksum_got": cf[15],
        },
    )


# ─── IBAN ──────────────────────────────────────────────────────────────


IBAN_PATTERN = re.compile(r"^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$")


def _iban_checksum(iban: str) -> bool:
    # Sposta i primi 4 char alla fine, converti A=10..Z=35, mod 97 == 1
    rearranged = iban[4:] + iban[:4]
    numeric = ""
    for c in rearranged:
        if c.isdigit():
            numeric += c
        else:
            numeric += str(ord(c) - ord("A") + 10)
    try:
        return int(numeric) % 97 == 1
    except ValueError:
        return False


@router.post("/iban", response_model=ValidationResult)
async def validate_iban(payload: dict) -> ValidationResult:
    iban = (payload.get("value") or "").upper().replace(" ", "").strip()
    if not IBAN_PATTERN.match(iban):
        return ValidationResult(valid=False, input=iban, details={"reason": "pattern"})
    valid = _iban_checksum(iban)
    return ValidationResult(
        valid=valid,
        input=iban,
        normalized=iban,
        details={"country": iban[:2], "check_digits": iban[2:4], "bban": iban[4:]},
    )


# ─── Partita IVA ───────────────────────────────────────────────────────


PIVA_PATTERN = re.compile(r"^[0-9]{11}$")


def _piva_checksum(piva: str) -> bool:
    s = 0
    for i, ch in enumerate(piva[:10]):
        n = int(ch)
        if i % 2 == 0:
            s += n
        else:
            n *= 2
            s += n if n < 10 else n - 9
    check = (10 - (s % 10)) % 10
    return check == int(piva[10])


@router.post("/partita-iva", response_model=ValidationResult)
async def validate_piva(payload: dict) -> ValidationResult:
    piva = (payload.get("value") or "").replace(" ", "").strip()
    if not PIVA_PATTERN.match(piva):
        return ValidationResult(valid=False, input=piva, details={"reason": "must_be_11_digits"})
    valid = _piva_checksum(piva)
    return ValidationResult(valid=valid, input=piva, normalized=piva,
                           details={"checksum_position": 11})


# ─── PEC email ─────────────────────────────────────────────────────────


# I provider PEC italiani noti (lista verificabile da Agid)
KNOWN_PEC_DOMAINS = {
    "pec.it", "legalmail.it", "pec.aruba.it", "arubapec.it",
    "pec.poste.it", "postecert.it", "cert.legalmail.it",
    "pec.libero.it", "pec.tim.it", "actaliscertymail.it",
    "registerpec.it", "pec.namirial.it", "pec.it.infocert.it",
    "pec.tin.it", "pec.lecbcc.it",
}

PEC_PATTERN = re.compile(r"^[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+)$")


@router.post("/pec", response_model=ValidationResult)
async def validate_pec(payload: dict) -> ValidationResult:
    email = (payload.get("value") or "").lower().strip()
    m = PEC_PATTERN.match(email)
    if not m:
        return ValidationResult(valid=False, input=email, details={"reason": "not_email"})
    domain = m.group(1)
    is_pec = domain in KNOWN_PEC_DOMAINS or any(p in domain for p in ("pec", "cert", "legalmail"))
    return ValidationResult(
        valid=is_pec, input=email, normalized=email,
        details={"domain": domain, "known_pec": domain in KNOWN_PEC_DOMAINS},
    )


@router.get("/health", response_model=dict)
async def health() -> dict:
    return {
        "validators": ["codice-fiscale", "iban", "partita-iva", "pec"],
        "calculators": ["codice-fiscale-calculator"],
        "note": "Validazione + calcolo algoritmici locali, niente API esterne.",
    }


# ─── Calcolatore Codice Fiscale ───────────────────────────────────────


class CFCalculatorRequest(BaseModel):
    cognome: str
    nome: str
    sesso: str  # "M" or "F"
    data_nascita: str  # "1985-08-01"
    comune_codice: str  # 4 char es "H501" (Roma). L'utente deve sapere il codice.


CF_MONTH_CODES = ["A", "B", "C", "D", "E", "H", "L", "M", "P", "R", "S", "T"]


def _extract_consonants_then_vowels(s: str, count: int) -> str:
    """Estrae N consonanti, poi vocali se mancanti, padding con X."""
    s_clean = "".join(c for c in s.upper() if c.isalpha())
    consonants = [c for c in s_clean if c not in "AEIOU"]
    vowels = [c for c in s_clean if c in "AEIOU"]
    out = consonants[:count]
    if len(out) < count:
        out += vowels[:count - len(out)]
    if len(out) < count:
        out += ["X"] * (count - len(out))
    return "".join(out[:count])


def _cf_cognome(cognome: str) -> str:
    return _extract_consonants_then_vowels(cognome, 3)


def _cf_nome(nome: str) -> str:
    """Per il nome: se ci sono ≥4 consonanti, prendi 1ª, 3ª, 4ª. Altrimenti 1ª, 2ª, 3ª."""
    s_clean = "".join(c for c in nome.upper() if c.isalpha())
    consonants = [c for c in s_clean if c not in "AEIOU"]
    vowels = [c for c in s_clean if c in "AEIOU"]
    if len(consonants) >= 4:
        cons_picked = [consonants[0], consonants[2], consonants[3]]
    else:
        cons_picked = consonants[:3]
    if len(cons_picked) < 3:
        cons_picked += vowels[:3 - len(cons_picked)]
    if len(cons_picked) < 3:
        cons_picked += ["X"] * (3 - len(cons_picked))
    return "".join(cons_picked[:3])


@router.post("/codice-fiscale/calculate", response_model=dict)
async def calculate_cf(req: CFCalculatorRequest) -> dict:
    try:
        year, month, day = map(int, req.data_nascita.split("-"))
    except (ValueError, AttributeError):
        raise HTTPException(400, {"code": "invalid_data_nascita",
                                    "hint": "Formato: YYYY-MM-DD"})

    if req.sesso.upper() not in ("M", "F"):
        raise HTTPException(400, {"code": "invalid_sesso", "hint": "M o F"})

    if not re.match(r"^[A-Z][0-9]{3}$", req.comune_codice.upper()):
        raise HTTPException(400, {"code": "invalid_comune_codice",
                                    "hint": "4 char es. H501 (Roma)"})

    # 6 char anagrafica
    surname = _cf_cognome(req.cognome)
    name = _cf_nome(req.nome)

    # 2 char anno
    year_code = str(year)[-2:]

    # 1 char mese
    month_code = CF_MONTH_CODES[month - 1]

    # 2 char giorno (+40 se femmina)
    day_n = day + 40 if req.sesso.upper() == "F" else day
    day_code = f"{day_n:02d}"

    # 4 char codice comune
    comune = req.comune_codice.upper()

    cf15 = surname + name + year_code + month_code + day_code + comune
    check = _cf_checksum(cf15)
    cf = cf15 + check

    return {
        "codice_fiscale": cf,
        "components": {
            "cognome": surname,
            "nome": name,
            "anno": year_code,
            "mese": month_code,
            "giorno": day_code,
            "comune": comune,
            "check": check,
        },
        "input": req.model_dump(),
    }
