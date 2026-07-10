---
name: python-dev
description: Python development best practices — code quality, testing, error handling, environment management, and tooling conventions. Reference skill for general Python development across projects.
argument-hint: '[focus: quality|testing|errors|environment|tooling]'
metadata:
  activation:
    signals:
      file_patterns: ["**/pyproject.toml", "**/*.py"]
    agents: [implementer, refactorer, code-critic]
    priority: recommended
---

# Python Development

General Python development guidance. Projects may override conventions
(e.g., docstring style, package manager) in their `copilot-instructions.md`.

## When to Use

- When writing or reviewing Python code
- When setting up development environments
- When choosing between libraries, patterns, or tooling
- When a project lacks its own Python conventions

## Code Quality Principles

1. **DRY** — Don't Repeat Yourself. Extract shared logic.
2. **Composition over inheritance** — prefer delegation and protocols.
3. **Pure functions when possible** — no side effects, easier to test.
4. **Simple over clever** — prioritise readability.
5. **Design for the common case first** — solve the 80% before edge cases.
6. **Small functions** — single responsibility, one purpose.

## Style Conventions

| Convention | Default | Notes |
|-----------|---------|-------|
| **Naming** | `snake_case` (functions/vars), `PascalCase` (classes), `UPPER_CASE` (constants) | Universal |
| **Type hints** | Required on all function signatures | Python 3.10+ union syntax: `X \| None` |
| **Docstrings** | NumPy-style (AF default) or Google-style | Check project `copilot-instructions.md` |
| **Imports** | No wildcard imports; `from __future__ import annotations` for forward refs | |
| **Private** | Prefix with `_` | |

### NumPy-Style Docstring

```python
def compute_result(data: list[float], threshold: float = 0.5) -> float:
    """Compute aggregated result from input data.

    Parameters
    ----------
    data : list[float]
        Input values to process.
    threshold : float, optional
        Minimum value to include, by default 0.5.

    Returns
    -------
    float
        Aggregated result.

    Raises
    ------
    ValueError
        If data is empty.
    """
```

### Google-Style Docstring

```python
def compute_result(data: list[float], threshold: float = 0.5) -> float:
    """Compute aggregated result from input data.

    Args:
        data: Input values to process.
        threshold: Minimum value to include. Defaults to 0.5.

    Returns:
        Aggregated result.

    Raises:
        ValueError: If data is empty.
    """
```

## Error Handling

- **Specific exceptions** — never bare `except:` or `except Exception:`
- **Validate inputs early** — check at function entry, fail fast
- **Context managers** — `with` statements for resources
- **Domain exceptions** — raise domain-specific exceptions in core logic

```python
class DataValidationError(Exception):
    """Raised when input data fails validation."""

def process_records(records: list[dict]) -> list[dict]:
    if not records:
        raise DataValidationError("Records list cannot be empty")

    try:
        return [transform(r) for r in records if r.get("status") == "active"]
    except KeyError as e:
        raise DataValidationError(f"Missing required field: {e}") from e
```

## Efficiency Patterns

| Pattern | Use | Example |
|---------|-----|---------|
| f-strings | String formatting | `f"Hello {name}"` |
| Comprehensions | List/dict/set creation | `[x for x in items if x > 0]` |
| Generators | Large iterables | `(x for x in items if x > 0)` |
| `pathlib.Path` | File paths | `Path("data") / "file.csv"` |
| `@dataclass` | Value objects | Reduced boilerplate |
| Walrus operator | Inline assignment | `if (n := len(items)) > 10:` |

## Testing

| Convention | Details |
|-----------|---------|
| Framework | **pytest** exclusively (no unittest) |
| Location | `tests/` directory with `__init__.py` |
| Naming | `test_*.py` files, `test_*` functions |
| Structure | AAA: Arrange → Act → Assert |
| Parametrize | `@pytest.mark.parametrize` for multiple inputs |
| Fixtures | `conftest.py` for shared fixtures |
| Property tests | `hypothesis` for wide input spaces |

```python
import pytest

def test_compute_result_basic():
    result = compute_result([1.0, 2.0, 3.0], threshold=0.5)
    assert result == pytest.approx(6.0)

def test_compute_result_empty_raises():
    with pytest.raises(DataValidationError, match="empty"):
        compute_result([])

@pytest.mark.parametrize("data,expected", [
    ([1.0], 1.0),
    ([1.0, 2.0], 3.0),
    ([0.1, 0.2, 0.3], pytest.approx(0.6)),
])
def test_compute_result_parametrized(data, expected):
    assert compute_result(data, threshold=0.0) == expected
```

## Environment Management

### Package Managers

| Tool | Command | When |
|------|---------|------|
| **pip + venv** | `pip install`, `python -m venv` | Traditional projects |
| **uv** | `uv sync`, `uv run` | Modern projects (fast, replaces pip+venv) |
| **conda** | `conda install` | Data science with C/Fortran deps |

**Check project convention.** If `pyproject.toml` exists with `[tool.uv]`,
use `uv`. If `requirements.txt` exists, use pip.

### uv Workflow

```bash
uv sync                    # Install from pyproject.toml
uv sync --extra dev        # With dev dependencies
uv run python script.py    # Run without activation
uv run pytest              # Run tests
uv add requests            # Add dependency
```

### pip + venv Workflow

```bash
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
.venv\Scripts\Activate.ps1 # Windows
pip install -r requirements.txt
pip install -e ".[dev]"    # Editable install with dev extras
```

## Linting & Formatting

| Tool | Purpose | Command |
|------|---------|---------|
| **Ruff** | Linting + formatting (replaces flake8, black, isort) | `ruff check .` / `ruff format .` |
| **mypy** | Type checking | `mypy src/` |
| **pyright** | Type checking (alternative) | `pyright` |
| **Bandit** | Security linting | `bandit -r src/` |

**Default:** Ruff for lint+format, mypy or pyright for types (check project).

## Anti-Patterns

| Anti-Pattern | Fix |
|---|---|
| Bare `except:` | Catch specific exceptions |
| Mutable default args (`def f(x=[])`) | Use `None` sentinel: `def f(x=None)` |
| `import *` | Explicit imports |
| Global mutable state | Dependency injection or module-level constants |
| Deep inheritance hierarchies | Composition + protocols |
| `type()` checks | `isinstance()` or protocols |

## References

- Python 3.11+ What's New: https://docs.python.org/3/whatsnew/
- Ruff: https://docs.astral.sh/ruff/
- uv: https://docs.astral.sh/uv/
- pytest: https://docs.pytest.org/
- mypy: https://mypy.readthedocs.io/
