"""SOLEM Backend Layers — L1-L7 implementati come moduli Python.

Ogni layer espone un APIRouter FastAPI che viene montato in solem_api.main.

  L1  identity   — chi è ogni utente (ruoli, valori, obiettivi, sezioni libere)
  L2  context    — dove/quando/cosa/ruolo attivo, snapshot 5min
  L3  events     — event bus pub/sub interno
  L4  capabilities (in main.py — auto-discovery)
  L5  memory     — 3 livelli: SOLEM, Utente, Contestuale
  L6  interop    — bridge esterni (Step 3+)
  L7  extensions — marketplace plugin (Step 4+)
"""
__all__ = ["identity", "context", "events", "memory"]
