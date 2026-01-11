import re
from pathlib import Path

AKIA_RE = re.compile(r'AKIA[0-9A-Z]{16}')

def mask_akia(s: str) -> str:
    def repl(m):
        v = m.group(0)
        return f"AKIA_REDACTED_{v[-4:]}"
    return AKIA_RE.sub(repl, s)

def main():
    base = Path("week2")
    changed = 0
    for p in base.rglob("*"):
        if p.is_file() and p.suffix.lower() in {".json", ".txt", ".md", ".log"}:
            data = p.read_text(errors="ignore")
            new = mask_akia(data)
            if new != data:
                p.write_text(new)
                changed += 1
                print(f"[masked] {p}")
    print(f"Done. Files changed: {changed}")

if __name__ == "__main__":
    main()
