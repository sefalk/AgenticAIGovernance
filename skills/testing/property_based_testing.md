---
category: testing
applies_to: [all]
complexity: advanced
maturity: draft
version: "1.0"
last_reviewed: 2026-02-26
related: [unit_testing, mutation_testing]
---
# Property-Based Testing

## Purpose

Property-based testing (PBT) verifies that code satisfies *general properties* over a wide range of automatically generated inputs, rather than checking specific input/output examples. Where unit tests say "given this input, expect that output," property-based tests say "for *all* valid inputs, this property must hold." PBT excels at discovering edge cases that humans would never think to test. Invoke this skill when the code under test has well-defined invariants, operates on structured data, or when exhaustive manual test case enumeration is impractical.

## Principles

- **Properties over examples:** Instead of specifying concrete expected outputs, define *invariants* -- relationships that must always hold between inputs and outputs.
- **Automated exploration:** The framework generates hundreds or thousands of random inputs, systematically exploring the input space. This is not fuzzing -- inputs are structurally valid and respect the data model.
- **Shrinking:** When a failing input is found, the framework automatically reduces it to the *minimal* failing case, making debugging trivial.
- **Verifiability (AAIG L1):** Property tests are programmatically verifiable and produce reproducible failures via seed-based random generation.
- **Efficiency (AAIG L1):** PBT has a high return-on-investment for algorithmic code, parsers, serializers, and stateful systems. It is less suited for UI-heavy or integration-dependent code.

## Techniques & Patterns

### Core Concepts

**Property:** A boolean assertion that must hold for all generated inputs. The art of PBT is choosing the right properties.

**Generator:** Produces random instances of a data type. Frameworks provide built-in generators for primitives and combinators to compose complex generators.

**Shrinker:** When a property fails, the shrinker reduces the failing input to the smallest case that still fails. E.g., a failing list `[7, 3, 42, 0, -1, 88]` might shrink to `[0]`.

### Property Categories

These are the canonical property types. Use them as a checklist when designing property tests.

#### 1. Round-Trip / Inverse Properties
Test that encoding/decoding, serialization/deserialization, or any invertible operation is lossless.

```
Property: For all X, decode(encode(X)) == X
```

**Use for:** JSON/XML/Protobuf serialization, compression, encryption/decryption, URL encoding, database read/write, parser/printer pairs.

#### 2. Idempotency
Test that applying an operation multiple times yields the same result as applying it once.

```
Property: For all X, f(f(X)) == f(X)
```

**Use for:** Sorting, formatting, normalization, deduplication, cache operations, HTTP PUT handlers.

#### 3. Invariant Preservation
Test that an operation preserves a known invariant of the data structure.

```
Property: For all operations Op on data structure D,
          invariant(D) implies invariant(Op(D))
```

**Use for:** Balanced trees (height invariant), sorted collections (order invariant), database constraints (referential integrity), financial systems (balance equation).

#### 4. Equivalence / Oracle
Test that two implementations produce the same result (one is the "oracle," usually simpler but slower).

```
Property: For all X, fast_implementation(X) == reference_implementation(X)
```

**Use for:** Optimized algorithms vs. brute force, new implementation vs. legacy, parallel vs. sequential.

#### 5. Metamorphic Properties
When you can't easily state the expected output, test relationships between inputs and outputs.

```
Property: sort(X + Y) == sort(sort(X) + sort(Y))
Property: length(filter(P, X)) <= length(X)
```

**Use for:** Machine learning models, numerical computation, search algorithms, any function where exact output is hard to specify.

#### 6. Inductive Properties
Test that a property holds for base cases and is preserved by construction.

```
Property: For all non-empty lists L,
          head(L) is an element of L
          length(L) == 1 + length(tail(L))
```

**Use for:** Recursive data structures, builder/constructor chains, step-by-step algorithms.

#### 7. Commutativity / Associativity / Algebraic Properties
Test algebraic laws that your operation should satisfy.

```
Property: merge(A, B) == merge(B, A)                [commutativity]
Property: merge(A, merge(B, C)) == merge(merge(A, B), C)  [associativity]
Property: apply(identity, X) == X                    [identity element]
```

**Use for:** Set operations, merge functions, reducers, CRDTs, mathematical operations.

### Stateful / Model-Based Testing

The most powerful PBT technique: test a *stateful* system by comparing it against a simplified *model*.

```
1. Define a model (e.g., a Python dict as a model for a custom hash map).
2. Generate random sequences of operations (put, get, delete, resize).
3. Apply each operation to both the real system and the model.
4. After each operation, assert that the observable state is equivalent.
```

**Use for:** Data structures, databases, caches, state machines, protocol implementations, concurrent systems.

**Frameworks:**
- Python: `hypothesis.stateful` (RuleBasedStateMachine)
- JS/TS: `fast-check` `fc.commands()` or `fc.modelRun()`
- Java: `jqwik` `@Property` with `ActionSequence`
- Haskell: `QuickCheck` `StateModel`

### Writing Effective Generators

**Composition:** Build complex generators from simple ones.

```python
# Python (Hypothesis)
from hypothesis import strategies as st

# Primitive generators
st.integers()
st.text()
st.booleans()

# Composite generators
st.lists(st.integers(), min_size=1, max_size=100)
st.tuples(st.text(), st.integers())
st.fixed_dictionaries({"name": st.text(), "age": st.integers(min_value=0, max_value=150)})

# Custom data class generator
@st.composite
def user_strategy(draw):
    name = draw(st.text(min_size=1, max_size=50))
    age = draw(st.integers(min_value=0, max_value=150))
    email = draw(st.emails())
    return User(name=name, age=age, email=email)
```

**Guidelines:**
- Constrain generators to produce *valid* inputs. PBT tests properties, not input validation (test that separately with unit tests).
- Use `assume()` sparingly -- it filters out generated values and wastes computation. Better to constrain the generator itself.
- Define reusable generators for domain types and share them across tests.

### Language-Specific Guidance

#### Python
- **Framework:** `Hypothesis` (the gold standard).
- **Usage:** `@given(st.integers(), st.integers())` decorator on test functions. Integrates natively with `pytest`.
- **Database strategy:** `hypothesis[django]` for Django model generation. `hypothesis[numpy]` for NumPy arrays.
- **Settings:** Use `@settings(max_examples=1000)` for thorough exploration, `@settings(max_examples=100)` for CI speed.
- **Profiles:** Define `hypothesis.settings.register_profile("ci", max_examples=200)` and `register_profile("dev", max_examples=50)`.

#### JavaScript / TypeScript
- **Framework:** `fast-check` (comprehensive and well-maintained).
- **Usage:** `fc.assert(fc.property(fc.integer(), fc.integer(), (a, b) => { ... }))`.
- **Integration:** Works with jest, vitest, mocha. Use `fc.configureGlobal({ numRuns: 1000 })` for defaults.
- **Async:** Supports `fc.asyncProperty()` for testing async code.

#### Java / Kotlin
- **Framework:** `jqwik` (preferred), `QuickTheories`, or `junit-quickcheck`.
- **Usage:** `@Property void myProperty(@ForAll int x, @ForAll @StringLength(max = 100) String s) { ... }`.
- **Arbitraries:** Use `Arbitraries.integers().between(0, 100)`, `.map()`, `.flatMap()`, `.filter()` for composition.
- **Edge cases:** jqwik automatically includes edge cases (0, MIN_VALUE, MAX_VALUE, empty strings, etc.).

#### Haskell
- **Framework:** `QuickCheck` (the original PBT framework) or `Hedgehog`.
- **Usage:** `prop_roundTrip x = decode (encode x) === x`. Use `quickCheck`, `verboseCheck`, or Hedgehog's `property`.
- **Generators:** `Arbitrary` type class. Derive with `Generic` or write custom `arbitrary` implementations.

#### Rust
- **Framework:** `proptest` (preferred) or `quickcheck`.
- **Usage:** `proptest! { #[test] fn my_prop(x in 0..100i32) { prop_assert!(f(x) >= 0); } }`.
- **Strategies:** `prop::collection::vec(0..100i32, 1..50)` for collections. Use `prop_flat_map` for dependent generation.

#### C# / .NET
- **Framework:** `FsCheck` (mature, originally F#) or `CsCheck`.
- **Usage:** `[Property] public Property RoundTrip(MyData data) => (Decode(Encode(data)) == data).ToProperty();`.
- **Generators:** Use `Arb.From<T>()` and `.Select()` / `.Where()` for composition.

## Quality Gates

| Gate | Default Threshold | Notes |
|------|------------------|-------|
| **Property count** | >= 1 per public invariant | Each documented invariant or algebraic property has a corresponding PBT test. |
| **Example count** | >= 200 per property (CI) | Number of random examples generated per property per run. Adjust via settings/profiles. |
| **Shrink quality** | Minimal failing case | Failing cases must be shrunk. If the framework reports unshrunk failures, investigate the generator/shrinker. |
| **No skips** | < 5% assumption rejections | `assume()` rejecting > 5% of generated values indicates a poorly constrained generator. |
| **Seed reproducibility** | 100% | All failures must be reproducible via the recorded seed. CI should log failing seeds. |

## Anti-Patterns

| Anti-Pattern | Problem | Fix |
|---|---|---|
| **Re-implementing the function** | The property test contains the same logic as the code under test. Always passes. | Use a different formulation: round-trip, oracle, metamorphic, or algebraic properties. |
| **Overly constrained generators** | Generators produce only a tiny fraction of the input space (e.g., `assume(x > 0 and x < 5)`). | Constrain the generator directly: `st.integers(min_value=1, max_value=4)`. |
| **Testing only trivial properties** | `Property: len(sort(x)) == len(x)`. True, but doesn't verify that sort actually sorts. | Combine multiple properties: length preservation AND pairwise ordering AND same elements. |
| **Ignoring shrunk output** | A failure is found but the developer fixes the specific case without understanding the pattern. | Read the shrunk case carefully -- it reveals the *category* of inputs that break the code. |
| **No stateful testing** | Using PBT only for pure functions, missing opportunities to test stateful systems. | Apply model-based testing for data structures, caches, and state machines. |
| **Flaky seeds** | Tests pass/fail depending on the random seed and developers just re-run. | Fix the code, not the seed. Log and archive all failing seeds. |


## See Also

- [Unit Testing](../testing/unit_testing.md)
- [Mutation Testing](../testing/mutation_testing.md)

## References

- Koen Claessen & John Hughes, "QuickCheck: A Lightweight Tool for Random Testing of Haskell Programs" (2000) -- the foundational PBT paper.
- David R. MacIver & Zac Hatfield-Dodds, "Hypothesis: A new approach to property-based testing" (2019) -- design of the Hypothesis framework.
- Fred Hebert, *Property-Based Testing with PropEr, Erlang, and Elixir* (2019) -- excellent practical guide, applicable beyond Erlang.
- Scott Wlaschin, ["Choosing properties for property-based testing"](https://fsharpforfunandprofit.com/posts/property-based-testing-2/) -- great primer on property categories.
- Hypothesis documentation: https://hypothesis.readthedocs.io/
- fast-check documentation: https://fast-check.dev/
- jqwik documentation: https://jqwik.net/
- proptest documentation: https://proptest-rs.github.io/proptest/
