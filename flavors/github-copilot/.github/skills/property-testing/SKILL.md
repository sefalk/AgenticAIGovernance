---
name: property-testing
description: Write property-based tests with hypothesis. Provides invariant templates, strategy patterns, and best practices for functions with wide input spaces or mathematical invariants.
argument-hint: '[function or module to test] [invariant type: preservation|bounded|idempotent|roundtrip]'
---

# Property-Based Testing Skill

Templates and guidance for writing property-based tests using **hypothesis**.

## When to Use

Use property-based tests when the function has:

- **Mathematical invariants** — chunking preserves elements, operations are idempotent
- **Wide input spaces** — dates, numeric ranges, strings
- **Boundary-sensitive logic** — off-by-one, inclusive/exclusive
- **Composition properties** — roundtrips, associativity
- **Conservation laws** — row counts preserved, sums unchanged

Do NOT use for simple getters, configuration, or fully covered parametrised tests.

## Quick Reference

```python
from hypothesis import given, assume, settings, example
from hypothesis import strategies as st
```

```bash
# Run property tests
pytest tests/properties/ -v --hypothesis-show-statistics

# More examples for thoroughness
pytest tests/properties/ -v --hypothesis-seed=0
```

## Property Templates

Use these categories as a **checklist** when designing property tests.
Every public invariant should have a corresponding property test using
at least one of these categories.

### 1. Round-Trip / Inverse

Test that an invertible operation is lossless: encoding/decoding,
serialization/deserialization, parser/printer pairs.

```
Property: For all X, decode(encode(X)) == X
```

```python
@given(x=st.text(min_size=0, max_size=50))
def test_encode_decode_roundtrip(x):
    """Encoding then decoding returns the original."""
    assert decode(encode(x)) == x
```

### 2. Idempotency

Test that applying an operation multiple times yields the same result
as applying it once.

```
Property: For all X, f(f(X)) == f(X)
```

```python
@given(x=st.integers(min_value=0, max_value=255))
def test_set_flag_is_idempotent(x):
    """Setting a flag already set does not change the value."""
    FLAG = 0x04
    assert (x | FLAG) == ((x | FLAG) | FLAG)
```

Use for: sorting, formatting, normalization, deduplication, cache operations.

### 3. Invariant Preservation

Test that an operation preserves a known invariant of the data structure.

```
Property: For all operations Op on data D,
          invariant(D) → invariant(Op(D))
```

```python
@given(lst=st.lists(st.integers(), max_size=100), n=st.integers(min_value=1, max_value=20))
def test_split_preserves_all_elements(lst, n):
    """Splitting then flattening returns the original list."""
    result = list(split(lst, n))
    flat = [item for chunk in result for item in chunk]
    assert flat == lst
```

Use for: balanced trees, sorted collections, database constraints, financial
systems (balance equations).

### 4. Equivalence / Oracle

Test that two implementations produce the same result. One is the "oracle"
(usually simpler but slower).

```
Property: For all X, fast_impl(X) == reference_impl(X)
```

```python
@given(data=st.lists(st.integers(), min_size=1, max_size=100))
def test_optimised_sum_matches_builtin(data):
    """Optimised implementation matches Python's built-in sum."""
    assert optimised_sum(data) == sum(data)
```

Use for: optimised vs brute-force, new vs legacy, parallel vs sequential.

### 5. Metamorphic Properties

When you can't easily state the expected output, test *relationships*
between inputs and outputs.

```
Property: sort(X + Y) == sort(sort(X) + sort(Y))
Property: length(filter(P, X)) <= length(X)
```

```python
@given(
    lst=st.lists(st.integers(), min_size=0, max_size=50),
    threshold=st.integers()
)
def test_filter_never_grows_list(lst, threshold):
    """Filtering never produces more elements than the input."""
    result = [x for x in lst if x > threshold]
    assert len(result) <= len(lst)
```

Use for: numerical computation, search algorithms, any function where exact
output is hard to specify.

### 6. Inductive Properties

Test that a property holds for base cases and is preserved by construction.

```
Property: For all non-empty lists L,
          head(L) is an element of L
          length(L) == 1 + length(tail(L))
```

```python
@given(lst=st.lists(st.integers(), min_size=1, max_size=100))
def test_head_is_member(lst):
    """First element is always a member of the list."""
    assert lst[0] in lst
```

Use for: recursive data structures, builder chains, step-by-step algorithms.

### 7. Commutativity / Associativity / Algebraic Laws

Test algebraic laws that your operation should satisfy.

```
Property: merge(A, B) == merge(B, A)         [commutativity]
Property: merge(A, merge(B, C)) == merge(merge(A, B), C)  [associativity]
Property: apply(identity, X) == X             [identity element]
```

```python
@given(a=st.integers(min_value=0, max_value=255), b=st.integers(min_value=0, max_value=255))
def test_bitwise_or_is_commutative(a, b):
    assert (a | b) == (b | a)

@given(x=st.integers(min_value=0, max_value=255))
def test_bitwise_or_zero_is_identity(x):
    assert (x | 0) == x
```

### 8. Bounded Output

```python
@given(lst=st.lists(st.integers(), min_size=1, max_size=100), n=st.integers(min_value=1, max_value=20))
def test_split_max_size_is_n(lst, n):
    """Every chunk has at most n elements."""
    assert all(len(chunk) <= n for chunk in split(lst, n))
```

### 9. Monotonicity / Ordering

```python
@given(data=st.data())
def test_date_range_is_sorted(data):
    """Output dates are always sorted ascending."""
    start = data.draw(st.dates())
    count = data.draw(st.integers(min_value=1, max_value=365))
    result = date_range(start, count)
    assert result == sorted(result)
```

### 10. Count Invariant

```python
@given(start=st.dates(), n=st.integers(min_value=1, max_value=365))
def test_date_range_returns_exact_count(start, n):
    """Returns exactly n dates."""
    assert len(date_range(start, n)) == n
```

### 11. No Side Effects

```python
@given(lst=st.lists(st.integers(), min_size=1, max_size=50))
def test_function_does_not_modify_input(lst):
    """Pure function does not mutate its inputs."""
    original = lst.copy()
    _ = my_function(lst)
    assert lst == original
```

### 12. Boundary Coverage

```python
@given(lst=st.lists(st.integers(), min_size=1, max_size=100))
def test_split_size_equals_list_returns_single_chunk(lst):
    """Chunk size equal to list length returns one chunk."""
    result = list(split(lst, len(lst)))
    assert len(result) == 1
```

## Property Discovery Checklist

| Question | Property Category |
|---|---|
| Can you undo with an inverse? | Round-trip (#1) |
| Is applying twice the same as once? | Idempotency (#2) |
| Does output preserve a structural invariant? | Invariant preservation (#3) |
| Is there a simpler reference implementation? | Equivalence / Oracle (#4) |
| Can you relate transformed inputs to outputs? | Metamorphic (#5) |
| Does it hold for base case and construction? | Inductive (#6) |
| Does it satisfy algebraic laws? | Algebraic (#7) |
| Does output respect size constraints? | Bounded output (#8) |
| Is output sorted/ordered? | Monotonicity (#9) |
| Is output length predictable? | Count invariant (#10) |
| Does it leave inputs unchanged? | No side effects (#11) |
| Does it work with empty/minimal inputs? | Boundary (#12) |

## Strategy Patterns

### Constrained Numerics
```python
st.floats(min_value=-1e6, max_value=1e6, allow_nan=False, allow_infinity=False)
st.integers(min_value=0, max_value=(1 << 8) - 1)  # bitmask
```

### Ordered Pairs
```python
st.tuples(st.dates(), st.dates()).map(lambda p: (min(p), max(p)))
```

### DataFrames (pandas)
```python
@st.composite
def sample_df(draw):
    n = draw(st.integers(min_value=1, max_value=50))
    return pd.DataFrame({
        "value": draw(st.lists(st.floats(allow_nan=False), min_size=n, max_size=n)),
    })
```

### Strings with Constraints
```python
st.from_regex(r"[A-Z][A-Z0-9_]{2,30}", fullmatch=True)
```

## Settings

| Criticality | `max_examples` |
|---|---|
| Standard | 100 (default) |
| Critical | 500 |
| Exploratory | 1000+ |
| Debugging | 1 + `@example(...)` |

## Anti-Patterns

| Anti-Pattern | Why It's Bad |
|---|---|
| `assert add(x, 0) == x` | Tests the language, not your domain |
| Reimplementing the function in the test | Duplicates bugs |
| `st.just(42)` | Defeats random generation |
| No `assume()` for preconditions | False failures |
| `@settings(max_examples=5)` | Insufficient exploration |
