---
name: pydantic
description: Use Pydantic for Python domain models, configuration, and data validation — BaseModel, field validators, serialization, settings, and integration with hexagonal architecture.
argument-hint: '[topic: domain-models|config|validation|serialization|settings]'
---

# Pydantic Skill

## When to Use

- Defining domain models or value objects in Python projects
- Validating external input at system boundaries (API payloads, config files, CLI args)
- Replacing plain `dataclass` or `dict` with validated, typed structures
- Defining application configuration with `pydantic-settings`
- Serializing/deserializing data to JSON, YAML, or other formats

## Principles

1. **Pydantic over dataclasses for domain models.** Pydantic provides
   runtime validation, serialization, and schema generation that plain
   dataclasses lack. Use `dataclass` only for simple internal data carriers
   with no validation needs.
2. **Validate at the boundary, trust inside.** Pydantic models belong at
   system boundaries (adapters, API handlers, config loaders). Domain core
   functions receive already-validated Pydantic instances — no redundant
   re-validation inside pure logic.
3. **Immutability by default.** Use `model_config = ConfigDict(frozen=True)`
   for domain models. Mutable models are acceptable for form/request objects
   that accumulate state before processing.
4. **Strict mode for external input.** Use `model_config = ConfigDict(strict=True)`
   or `@field_validator(..., mode='before')` when parsing untrusted data to
   prevent silent type coercion.

## Domain Models (Hexagonal Architecture)

Domain models live in the **Domain Core** layer. They import nothing from
adapters or infrastructure.

```python
from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class Movement(BaseModel):
    """A validated domain model for a movement window."""

    model_config = ConfigDict(frozen=True)

    system_id: str
    start_time: float
    end_time: float
    parameter: str
    value: float = Field(ge=0)
```

### When to Use `BaseModel` vs `dataclass`

| Use Case | Recommendation |
|---|---|
| Domain model with validation rules | `BaseModel` |
| Value object with equality semantics | `BaseModel(frozen=True)` |
| Simple internal data carrier (no validation) | `dataclass` |
| Configuration / settings | `BaseSettings` |
| DTO for API serialization | `BaseModel` |

## Field Validation

Use Pydantic's built-in constraints and custom validators:

```python
from pydantic import BaseModel, Field, field_validator


class AcquisitionWindow(BaseModel):
    """Validated acquisition window parameters."""

    index: int = Field(ge=0, description="AQC_INDEX value")
    duration_ms: float = Field(gt=0)
    protocol: str = Field(min_length=1, max_length=100)

    @field_validator("protocol")
    @classmethod
    def protocol_not_empty(cls, v: str) -> str:
        if not v.strip():
            return v
        return v.strip()
```

### Validation Best Practices

- Use `Field(ge=0)`, `Field(gt=0)`, `Field(le=100)` for numeric constraints
- Use `field_validator` for complex cross-field or business logic validation
- Use `model_validator(mode='after')` for multi-field consistency checks
- Raise `ValueError` from validators — Pydantic wraps it in `ValidationError`
- Never catch `ValidationError` silently — let it propagate or translate to
  a domain-specific exception at the adapter boundary

## Configuration with pydantic-settings

Use `pydantic-settings` for application configuration:

```python
from pydantic import Field
from pydantic_settings import BaseSettings


class PipelineConfig(BaseSettings):
    """Pipeline configuration from environment variables."""

    model_config = ConfigDict(env_prefix="PIPELINE_")

    source_table: str
    target_table: str
    batch_size: int = Field(default=1000, ge=1)
    dry_run: bool = False
```

## Serialization

```python
# To dict (for DataFrame construction, etc.)
movement.model_dump()

# To JSON string
movement.model_dump_json()

# From dict
Movement.model_validate(raw_dict)

# From JSON
Movement.model_validate_json(json_string)
```

## Integration with Hexagonal Architecture

| Layer | Pydantic Usage |
|---|---|
| **Domain Core** | `BaseModel` for domain models, value objects, exceptions |
| **Ports** | Type hints referencing domain models in `Protocol` methods |
| **Adapters** | `BaseModel` for DTOs; convert external data → domain models |
| **Orchestrators** | `BaseSettings` for pipeline configuration |

### Adapter Pattern — Parse External Data

```python
class RawTelegramDTO(BaseModel):
    """DTO for raw telegram data from external source."""

    model_config = ConfigDict(extra="ignore")  # tolerate unknown fields

    sys_id: str
    timestamp: str
    params: dict[str, float]


def to_domain(dto: RawTelegramDTO) -> Telegram:
    """Convert adapter DTO to domain model."""
    return Telegram(
        system_id=dto.sys_id,
        time=float(dto.timestamp),
        parameters=dto.params,
    )
```

## Testing Pydantic Models

```python
import pytest
from pydantic import ValidationError


def test_movement_rejects_negative_value():
    with pytest.raises(ValidationError, match="greater than or equal to 0"):
        Movement(system_id="X1", start_time=0, end_time=1,
                 parameter="kV", value=-1)


def test_movement_frozen():
    m = Movement(system_id="X1", start_time=0, end_time=1,
                 parameter="kV", value=80)
    with pytest.raises(ValidationError):
        m.value = 90  # frozen=True prevents mutation
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using `dict` for structured data | Define a `BaseModel` |
| Mutable domain models | Add `ConfigDict(frozen=True)` |
| Validating inside domain functions | Validate at the boundary (adapter) |
| Catching `ValidationError` silently | Let it propagate or translate |
| Using `validator` (v1 API) | Use `field_validator` (v2 API) |
| Using `Config` inner class (v1) | Use `model_config = ConfigDict(...)` (v2) |

## References

- [Pydantic v2 docs](https://docs.pydantic.dev/latest/)
- [pydantic-settings](https://docs.pydantic.dev/latest/concepts/pydantic_settings/)
